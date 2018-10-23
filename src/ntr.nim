import strutils, strformat, strtabs, os, osproc, sequtils, parseopt, terminal
import chroma

type Context = StringTableRef

const
  help = """
Usage: ntr [OPTIONS] [OUTPUT FILES]

Arguments:
  Context files supplied as arguments and sourced from pwd or from ntrDirectory/contexts

Options:
  -i, --in        add input file from pwd or from ntrDirectory/templates
  -I, --inplace   add input file and modify it in-place
  -o, --out       add output file
  -p, --profile   specify profile file
  --noDefaultProfile, --ndp     disable default profile
  --noDefaultContext, --ndc     disable default context
  --noDefaultFinisher, --ndf    disable default finisher
  --override      specify context addition/overrides
  --backup        backup existing files
  -e, --empty     allow empty context
  -E              force empty context
  -f              force execution of finishers
  -F              disable execution of finishers
  -d              only use files from ntrDirectory
  -D              never use files from ntrDirectory
  -h, --help      print this message
  -v, --version   print version number

If no profile or input files specified, input/output pairs are read from ntrDirectory/profile.
Specifying both -d and -D negates both options.
"""
  gitrev = staticExec "git describe --tags --long --dirty | sed -E 's/-.+-/ /'"
  version = &"ntr {gitrev} compiled at {CompileDate} {CompileTime}"
  illegalChars = {'.', '{', '}', '<', '>', ':', '$', '|'} + Whitespace
  envPrefix = "NTR_"
  emptySet: set[char] = {}

let emptyContext = newStringTable()

proc abortWith(s: string, n = 1) = stderr.writeLine s; quit n

func newContext*: Context = newStringTable()

func leadWs(s: string): int =
  for c in s:
    if c in Whitespace: inc result else: break

func isIdentifier(s: string): bool =
  for c in s:
    if c in illegalChars:
      return false
  true

func isExportable(s: string): bool =
  if s[0] in IdentStartChars:
    for i in 1..<s.high:
      if s[i] notin IdentChars:
        return false
    true
  else: false

proc renderFile*(file: string, c = emptyContext): string
proc render*(text: string, c = emptyContext): string

proc parseId(c: var Context, k, v: string, p = "") {.inline.} =
  if k.endsWith('*') and k.isExportable:
    let k = k[0..^2].strip(trailing = true)
    putEnv(envPrefix & k, v)
    c[p & k] = v
  elif k.isIdentifier:
    c[p & k] = v

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
        v = t[1].strip
      for k in t[0].split ',':
        parseId c, k.strip, v, prefix

proc addContextFile*(c: var Context, file: string) =
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for t in file.lines:
    let line = t.render
    contextRoutine c

proc addContext*(c: var Context, text: string) =
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for t in text.splitLines:
    let line = t.render
    contextRoutine c

proc getContext*(s: string): Context =
  result = newContext()
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for t in s.splitLines:
    let line = t.render
    contextRoutine result

template cmdColor(a): untyped =
  proc `cmd a`(c, v: string): string =
    try:
      if c.startsWith "#":
        "#" & c.parseHtmlHex.`a`(v.parseFloat).toHex
      else: c.parseHex.`a`(v.parseFloat).toHex
    except ValueError:
      stderr.writeLine "Couldn't parse value: " & v
      ""
    except InvalidColor:
      stderr.writeLine "Couldn't parse color: " & c
      ""

cmdColor lighten
cmdColor darken
cmdColor saturate
cmdColor desaturate

proc parseCmd(s: string, c: Context): string =
  if s.startsWith "$":
    getEnv s[1..^1]
  elif s.startsWith "e:":
    strip execProcess strip s[2..^1]
  elif s.startsWith "strip:":
    let
      a = s[6..^1].split ':'
      b = (if a.len > 0: a[1].foldl(a + {b}, emptySet) else: Whitespace)
    strip((if a[0] in c: c[a[0]] else: a[0]), chars = b)
  elif s.startsWith "lighten:":
    let a = s[8..^1].split ':'
    cmdLighten a[0], a[1]
  elif s.startsWith "darken:":
    let a = s[7..^1].split ':'
    cmdDarken a[0], a[1]
  elif s.startsWith "saturate:":
    let a = s[9..^1].split ':'
    cmdSaturate a[0], a[1]
  elif s.startsWith "desaturate:":
    let a = s[11..^1].split ':'
    cmdDesaturate a[0], a[1]
  elif s.count('|') > 0:
    let a = s.split '|'
    if a[0] in c:
      c[a[0]]
    elif a.len > 0:
      a[1]
    else: ""
  elif s in c:
    c[s]
  else: ""

template renderRoutine(res: var string, t: string): untyped =
  var
    i = t.high
    os = newSeq[int]()
    r = t
  while i >= t.low:
    let o = r.rfind("<{", i)
    if o != -1:
      i = o - 1
      os.add o
    else: break
  for o in os:
    let close = r.find("}>", o)
    if close != -1:
      r = r[0..<o] &
          r[o + 2..<close].strip.parseCmd(c) &
          r[close + 2..^1]
  res &= r & "\p"

proc renderFile*(file: string, c = emptyContext): string =
  for line in file.lines:
    renderRoutine result, line
  result.setLen result.high

proc renderStdin*(c = emptyContext): string =
  for line in stdin.lines:
    renderRoutine result, line
  result.setLen result.high

proc render*(text: string, c = emptyContext): string =
  for line in text.splitLines:
    renderRoutine result, line
  result.setLen result.high

proc parseProfile*(file: string, i, o: var seq[string]) =
  for k, v in file.renderFile.getContext:
    i.add k
    o.add v

when isMainModule:
  let
    ntrDir         = getConfigDir() / "ntr"
    ntrProfiles    = ntrDir / "profiles"
    ntrContexts    = ntrDir / "contexts"
    ntrTemplates   = ntrDir / "templates"
    ntrFinishers   = ntrDir / "finishers"
    ntrDefProfile  = ntrProfiles / "default"
    ntrDefContext  = ntrContexts / "default"
    ntrDefFinisher = ntrFinishers / "default"
  var
    inFiles           = newSeq[string]()
    outFiles          = newSeq[string]()
    contextFiles      = newSeq[string]()
    profileFile       = ""
    context           = newContext()
    overrideContext   = newContext()
    onlyDef           = false
    onlyExt           = false
    defaultProfile    = true
    defaultContext    = true
    defaultFinisher   = true
    doBackup          = false
    doFinish          = 0
    allowEmptyContext = false
    forceEmpty        = false

  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      contextFiles.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "in", "i": inFiles.add val
      of "out", "o": outFiles.add val
      of "inplace", "I":
        inFiles.add val
        outFiles.add val
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
      of "empty", "e": allowEmptyContext = true
      of "E":
        forceEmpty = true
        allowEmptyContext = true
      of "f": doFinish = 1
      of "F": doFinish = -1
      of "help", "h": abortWith help, 0
      of "version", "v": abortWith version, 0
      else: abortWith &"Couldn't parse command line argument: {key}"
    of cmdEnd: discard

  if onlyDef and onlyExt:
    onlyDef = false
    onlyExt = false

  if profileFile.len > 0:
    if not onlyDef and existsFile profileFile:
      parseProfile profileFile, inFiles, outFiles
    elif not onlyExt and existsFile ntrProfiles / profileFile:
      parseProfile ntrProfiles / profileFile, inFiles, outFiles
    else:
      abortWith &"File `{profileFile}` does not exist"

  if inFiles.len != outFiles.len:
    abortWith "Input/output files mismatch"

  if not forceEmpty:
    if defaultContext and not onlyExt and existsFile ntrDefContext:
      context.addContextFile ntrDefContext

    for file in contextFiles:
      if not onlyDef and existsFile file:
        context.addContextFile file
      elif not onlyExt and existsFile ntrContexts / file:
        context.addContextFile ntrContexts / file
      else:
        abortWith &"File `{file}` does not exist"

    for key, val in overrideContext:
      context[key] = val

  if not allowEmptyContext and context.len == 0:
    abortWith "Empty context"

  if not stdin.isatty:
    defaultProfile = false
    echo renderStdin context

  if defaultProfile and inFiles.len == 0 and ntrDefProfile.existsFile:
    if doFinish == 0: doFinish = 1
    ntrDefProfile.parseProfile inFiles, outFiles

  for i, file in inFiles:
    var output = ""
    if not onlyDef and existsFile file:
      output = file.renderFile context
    elif not onlyExt and existsFile ntrTemplates / file:
      output = (ntrTemplates / file).renderFile context
    else:
      abortWith &"File `{file}` does not exist"
    let outfile = outFiles[i]
    if outfile == "--":
      echo output
    else:
      let dir = parentDir outfile
      if doBackup and existsFile outfile:
        try:
          copyFileWithPermissions outfile, outfile & ".bak"
        except:
          abortWith &"Couldn't backup `{outfile}`."
      elif not existsDir dir:
        try:
          createDir dir
        except:
          abortWith &"Couldn't create directory `{dir}`."
      try:
        outfile.writeFile output
      except:
        abortWith &"Couldn't write to `{outfile}`."

  if doFinish == 1:
    for i in inFiles:
      let f = ntrFinishers / i.extractFilename
      if existsFile f:
        try:
          let errC = execCmd f
          if errC != 0:
            stderr.writeLine &"Finisher `{f}` exited with {errC}"
        except:
          stderr.writeLine &"Couldn't run finisher `{f}`"
    if defaultFinisher and existsFile ntrDefFinisher:
      try:
        let errC = execCmd ntrDefFinisher
        if errC != 0:
          stderr.writeLine &"Default finisher exited with {errC}"
      except:
        stderr.writeLine &"Couldn't run default finisher"
