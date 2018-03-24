import strutils, sequtils, tables, os, ospaths, osproc, parseopt, strformat

type Context = TableRef[string, string]

const
  help = """
Usage: ntr [OPTIONS] [OUTPUT FILES]

Arguments:
  arguments are passed as output files to corresponding input files

Options:
  -i, --in        add input file from pwd or from ntrDirectory/templates
  -c, --context   add context file from pwd or from ntrDirectory/contexts
  -p, --profile   specify profile file
  -o, --override  specify context addition/overrides
  --stdin         additionally read context from stdin
  -d              only use files from ntrDirectory
  -D              never use files from ntrDirectory
  -h, --help      print this message
  -v, --version   print version number

If no profile or input files specified, input/output pairs are read from ntrDirectory/profile.
Specifying both -d and -D negates both options.
"""
  gitrev = staticExec "git rev-parse --short HEAD"
  version = &"ntr v0.1.4 {gitrev} compiled at {CompileDate} {CompileTime}"

proc abortWith(s: string, n = 1) = echo s; quit n

proc newContext*: Context = newTable[string, string]()

proc put[A, B](t: var TableRef[A, B] | Table[A, B], k: A, v: B) {.inline.} =
  if k in t: t[k] = v
  else: t.add k, v

proc leadWhite(s: string): int =
  for c in s:
    if c in Whitespace: inc result else: break

template contextRoutine(c: var Context): untyped =
  let
    ws = line.leadWhite
    l = line.strip
  if l.len > 0 and l[0] != '#':
    if pad.len > 0 and ws <= pad[^1]:
      while pad.len > 0 and ws <= pad[^1]:
        pad.del pad.high
        prefixes.del prefixes.high
      prefix = prefixes.foldl(a & b & '.', "")
    if l.find(':') == -1:
      pad.add ws
      prefixes.add l
      prefix &= l & '.'
    else:
      let t = l.split(':', 1)
      for k in t[0].split ',':
        c.put prefix & k.strip, t[1].strip

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
  if s.startsWith "e.":
    getEnv s[2..^1]
  elif s.startsWith "e:":
    strip execProcess quoteShellPosix strip s[2..^1]
  elif s in c:
    c[s]
  else: ""

proc renderFile*(file: string, c: Context = newContext()): string =
  result = ""
  for line in file.lines:
    var
      i = line.high
      opens = newSeq[int]()
      res = line
    while true:
      let open = line.rfind("{{", i)
      if open > 0:
        i = open - 1
        opens.add open
      else: break
    for o in countdown(opens.high, 0):
      let
        open = opens[o]
        close = res.find("}}", open + 2)
      if close > 0:
        res = res[0..<open] &
              res[open + 2..<close].strip.parseCmd(c) &
              res[close + 2..^1]
    result &= res & '\n'
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
  var
    inFiles = newSeq[string]()
    outFiles = newSeq[string]()
    contextFiles = newSeq[string]()
    profileFile = ""
    context = newContext()
    overrideContext = newContext()
    onlyDef = false
    onlyExt = false
    readStdin = false

  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      outFiles.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "in", "i": inFiles.add val
      of "context", "c": contextFiles.add val
      of "profile", "p": profileFile = val
      of "override", "o":
        let t = val.split(':', 1)
        if t.len == 2:
          overrideContext.add t[0].strip, t[1].strip
        else: abortWith &"Incorrect override: {val}"
      of "stdin": readStdin = true
      of "d": onlyDef = true
      of "D": onlyExt = true
      of "help", "h": abortWith help, 0
      of "version", "v": abortWith version, 0
      else: abortWith &"Couldn't parse command line argument: {key}"
    of cmdEnd: discard

  if profileFile.existsFile:
    profileFile.parseProfile inFiles, outFiles

  if inFiles.len != outFiles.len:
    abortWith "Input/output files mismatch"

  if inFiles.len == 0 and ntrProfile.existsFile:
    ntrProfile.parseProfile inFiles, outFiles

  if onlyDef and onlyExt:
    onlyDef = false
    onlyExt = false

  for file in contextFiles:
    if not onlyDef and existsFile file:
      context.addContextFile file
    elif not onlyExt and existsFile ntrContexts / file:
      context.addContextFile ntrContexts / file
    else:
      abortWith &"File {file} does not exist"

  for key, val in overrideContext:
    context.put key, val

  if readStdin:
    context.addContext stdin.readAll

  if context.len == 0:
    abortWith "No context given"

  for i, file in inFiles:
    var output = ""
    if not onlyDef and existsFile file:
      output = file.renderFile context
    elif not onlyExt and existsFile ntrTemplates / file:
      output = (ntrTemplates / file).renderFile context
    else:
      abortWith &"File {file} does not exist"
    try:
      outFiles[i].writeFile output
    except:
      abortWith &"Couldn't write to {outFiles[i]}."
