import strutils, sequtils, tables, os, ospaths, osproc, parseopt, strformat

type Context = TableRef[string, string]

const
  help = """
ntr [OPTIONS] [OUTPUT FILES]

-i|--in        add input file
-c|--context   add context file
-p|--profile   specify profile file
-o|--override  specify context addition/overrides
-h|--help      print this message
-v|--version   print version number
"""
  version = "v0.1.0"

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
  if l.len > 0:
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
      c.put prefix & t[0].strip, t[1].strip

proc addContextFile*(c: var Context, file: string) =
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for line in file.lines:
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

#proc render(text: string, c: Context): string =
  #result = text
  #var
    #idx = 0
    #opens = newSeq[int]()
  #while true:
    #let idxOpen = text.find("{{", idx)
    #if idxOpen > 0:
      #idx = idxOpen + 2
      #opens.add idxOpen
    #else: break
  #for i in countdown(opens.high, 0):
    #let open = opens[i]
    #let close = result.find("}}", opens[i] + 2)
    #if close > 0:
      #result = result[0..<open] &
               #result[open + 2..<close].strip.parseCmd(c) &
               #result[close + 2..^1]

proc renderFile*(file: string, c: Context = newContext()): string =
  result = ""
  for line in file.lines:
    var
      i = 0
      opens = newSeq[int]()
      res = line
    while true:
      let open = line.find("{{", i)
      if open > 0:
        i = open + 2
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
  let profile = file.renderFile
  for k, v in profile.getContext:
    i.add k
    o.add v

when isMainModule:
  let
    ntrDir = if existsEnv "XDG_CONFIG_HOME": "XDG_CONFIG_HOME".getEnv & "/ntr"
    else: getConfigDir().expandTilde & "ntr"
    ntrProfile = ntrDir & "/profile"
  var
    inFiles = newSeq[string]()
    outFiles = newSeq[string]()
    contextFiles = newSeq[string]()
    profileFile = ""
    context = newContext()
    overrideContext = newContext()

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
        overrideContext.add t[0].strip, t[1].strip
      of "help", "h": abortWith help, 0
      of "version", "v": abortWith version, 0
      else:
        abortWith &"Couldn't parse command line argument: {key}"
    of cmdEnd: discard

  if profileFile.existsFile:
    profileFile.parseProfile inFiles, outFiles

  if inFiles.len != outFiles.len:
    abortWith "Input/output files mismatch"

  if inFiles.len == 0 and ntrProfile.existsFile:
    ntrProfile.parseProfile inFiles, outFiles

  for file in contextFiles:
    if file.existsFile:
      context.addContextFile file
    else:
      abortWith &"File {file} does not exist"

  for key, val in overrideContext:
    context.put key, val

  for i, file in inFiles:
    if file.existsFile:
      try:
        outFiles[i].writeFile file.renderFile context
      except:
        abortWith &"Couldn't write to {outFiles[i]}."
    else:
      abortWith &"File {file} does not exist"
