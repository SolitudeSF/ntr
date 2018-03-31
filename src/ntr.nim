import strutils, sequtils, tables, os, ospaths, osproc, parseopt, strformat, terminal

type Context = TableRef[string, string]

const
  help = """
Usage: ntr [OPTIONS] [OUTPUT FILES]

Arguments:
  Context files supplied as arguments and sourced from pwd or from ntrDirectory/contexts

Options:
  -i, --in        add input file from pwd or from ntrDirectory/templates
  -o, --out       add output file
  -p, --profile   specify profile file
  --noDefaultProfile, --ndp     disable default profile
  --noDefaultContext, --ndc     disable default context
  --noDefaultFinisher, --ndf    disable default finisher
  --override      specify context addition/overrides
  --backup        backup existing files
  -e, --empty     allow empty context
  -E              force empty context
  -d              only use files from ntrDirectory
  -D              never use files from ntrDirectory
  -h, --help      print this message
  -v, --version   print version number

If no profile or input files specified, input/output pairs are read from ntrDirectory/profile.
Specifying both -d and -D negates both options.
"""
  gitrev = staticExec "git describe --tags --long --dirty | sed -E 's/-.+-/ /'"
  version = &"ntr {gitrev} compiled at {CompileDate} {CompileTime}"
  illegalChars = {'.', '{', '}', ':', '$'} + Whitespace

proc abortWith(s: string, n = 1) = stderr.writeLine s; quit n

proc newContext*: Context = newTable[string, string]()

proc put[A, B](t: var TableRef[A, B] | Table[A, B], k: A, v: B) {.inline.} =
  if k in t: t[k] = v
  else: t.add k, v

proc leadWs(s: string): int =
  for c in s:
    if c in Whitespace: inc result else: break

proc isIdentifier(s: string): bool =
  for c in s:
    if c in illegalChars:
      return false
  true

proc isExportable(s: string): bool =
  if s[0] in IdentStartChars:
    for i in 1..<s.high:
      if s[i] notin IdentChars:
        return false
    true
  else: false

proc render*(text: string, c = newContext()): string

proc parseId(c: var Context, k, v: string, p = "") {.inline.} =
  if k.endsWith('*') and k.isExportable:
    var k = k[0..^2]
    k = k.strip(trailing = true)
    putEnv k, v
    c.put p & k, v
  elif k.isIdentifier:
    c.put p & k, v

template contextRoutine(c: var Context): untyped =
  let
    ws = line.leadWs
    l = line.strip
  if l.len > 0 and l[0] != '#':
    if pad.len > 0 and ws <= pad[^1]:
      while pad.len > 0 and ws <= pad[^1]:
        pad.del pad.high
        prefixes.del prefixes.high
      prefix = prefixes.foldl(a & b & '.', "")
    if l.find(':') == -1:
      if not l.isIdentifier:
        abortWith "Illegal section name: " & l
      pad.add ws
      prefixes.add l
      prefix &= l & '.'
    else:
      let
        t = l.split(':', 1)
        v = t[1].render.strip
      for k in t[0].split ',':
         parseId c, k.strip, v, prefix

proc addContextFile*(c: var Context, file: string) =
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for line in file.lines:
    contextRoutine c

proc addContext*(c: var Context, text: string) =
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for line in text.splitLines:
    contextRoutine c

proc getContext*(s: string): Context =
  result = newContext()
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for line in s.splitLines:
    contextRoutine result

proc parseCmd(s: string, c: Context): string =
  if s.startsWith "$":
    getEnv s[1..^1]
  elif s.startsWith "e:":
    strip execProcess quoteShellPosix strip s[2..^1]
  elif s in c:
    c[s]
  else: ""

template renderRoutine(res: var string, t: string): untyped =
  var
    i = t.high
    os = newSeq[int]()
    r = t
  while i >= t.low:
    let o = r.rfind("{{", i)
    if o != -1:
      i = o - 1
      os.add o
    else: break
  for o in os:
    let close = r.find("}}", o)
    if close != -1:
      r = r[0..<o] &
          r[o + 2..<close].strip.parseCmd(c) &
          r[close + 2..^1]
  res &= r
  res &= "\p"

proc renderFile*(file: string, c = newContext()): string =
  result = ""
  for line in file.lines:
    renderRoutine result, line
  result.setLen result.high

proc renderStdin*(c = newContext()): string =
  result = ""
  for line in stdin.lines:
    renderRoutine result, line
  result.setLen result.high

proc render*(text: string, c = newContext()): string =
  result = ""
  for line in text.splitLines:
    renderRoutine result, line
  result.setLen result.high

proc parseProfile*(file: string, i, o: var seq[string]) =
  for k, v in file.renderFile.getContext:
    i.add k
    o.add v

when isMainModule:
  let
    ntrDir =
      if existsEnv "XDG_CONFIG_HOME":
        "XDG_CONFIG_HOME".getEnv / "ntr"
      else: getConfigDir().expandTilde / "ntr"
    ntrProfile = ntrDir / "default"
    ntrTemplates = ntrDir / "templates"
    ntrContexts = ntrDir / "contexts"
    ntrFinishers = ntrDir / "finishers"
  var
    inFiles = newSeq[string]()
    outFiles = newSeq[string]()
    contextFiles = newSeq[string]()
    profileFile = ""
    context = newContext()
    overrideContext = newContext()
    onlyDef = false
    onlyExt = false
    defaultProfile = true
    defaultContext = true
    defaultFinisher = true
    doBackup = false
    doFinish = 0
    emptyContext = false
    forceEmpty = false

  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      contextFiles.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "in", "i": inFiles.add val
      of "out", "o": outFiles.add val
      of "profile", "p": profileFile = val
      of "override", "r":
        let t = val.split(':', 1)
        if t.len == 2:
          overrideContext.parseId t[0].strip, t[1].strip
        else: abortWith &"Incorrect override: {val}"
      of "backup": doBackup = true
      of "noDefaultProfile", "ndp": defaultProfile = false
      of "noDefaultContext", "ndc": defaultContext = false
      of "noDefaultFinisher", "ndf": defaultFinisher = false
      of "d": onlyDef = true
      of "D": onlyExt = true
      of "empty", "e": emptyContext = true
      of "E":
        forceEmpty = true
        emptyContext = true
      of "f": doFinish = 1
      of "F": doFinish = -1
      of "help", "h": abortWith help, 0
      of "version", "v": abortWith version, 0
      else: abortWith &"Couldn't parse command line argument: {key}"
    of cmdEnd: discard

  if profileFile.existsFile:
    profileFile.parseProfile inFiles, outFiles

  if inFiles.len != outFiles.len:
    abortWith "Input/output files mismatch"

  if onlyDef and onlyExt:
    onlyDef = false
    onlyExt = false

  if not forceEmpty:
    if defaultContext and not onlyExt and existsFile ntrContexts / "default":
      context.addContextFile ntrContexts / "default"

    for file in contextFiles:
      if not onlyDef and existsFile file:
        context.addContextFile file
      elif not onlyExt and existsFile ntrContexts / file:
        context.addContextFile ntrContexts / file
      else:
        abortWith &"File {file} does not exist"

    for key, val in overrideContext:
      context.put key, val

  if not emptyContext and context.len == 0:
    abortWith "Empty context"

  if not stdin.isatty:
    let stdoutput = renderStdin context
    if stdoutput.len > 0:
      defaultProfile = false
      echo stdoutput

  if defaultProfile and inFiles.len == 0 and ntrProfile.existsFile:
    if doFinish == 0: doFinish = 1
    ntrProfile.parseProfile inFiles, outFiles

  for i, file in inFiles:
    var output = ""
    if not onlyDef and existsFile file:
      output = file.renderFile context
    elif not onlyExt and existsFile ntrTemplates / file:
      output = (ntrTemplates / file).renderFile context
    else:
      abortWith &"File {file} does not exist"
    if outFiles[i] == "--":
      echo output
    else:
      let dir = parentDir outFiles[i]
      if doBackup and existsFile outFiles[i]:
        try:
          copyFileWithPermissions outFiles[i], outFiles[i] & ".bak"
        except:
          abortWith &"Couldn't backup {outFiles[i]}."
      elif not existsDir dir:
        try:
          createDir dir
        except:
          abortWith &"Couldn't create directory chain {dir}."
      try:
        outFiles[i].writeFile output
      except:
        abortWith &"Couldn't write to {outFiles[i]}."

  if doFinish == 1:
    for i in inFiles:
      let f = ntrFinishers / i.extractFilename
      if existsFile f:
        try:
         let errC = execCmd f
         if errC != 0:
          stderr.writeLine &"Finisher {f} exited with {errC}"
        except:
          stderr.writeLine &"Couldn't run finisher {f}"
    let f = ntrFinishers / "default"
    if defaultFinisher and existsFile f:
      try:
        let errC = execCmd f
        if errC != 0:
          stderr.writeLine &"Default finisher exited with {errC}"
      except:
        stderr.writeLine &"Couldn't run default finisher"
