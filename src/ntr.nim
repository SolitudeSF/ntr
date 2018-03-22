import strutils, sequtils, tables, os, ospaths, osproc, parseopt, strformat

type
  Context = TableRef[string, string]

proc abortWith(s: string, n = 1) =
  echo s
  quit n

proc put[A, B](t: var TableRef[A, B] | Table[A, B], k: A, v: B) {.inline.} =
  if k in t: t[k] = v
  else: t.add k, v

proc leadWhite(s: string): int =
  for c in s:
    if c in Whitespace: inc result else: break

proc addContext*(c: var Context, file: string) =
  c = newTable[string, string]()
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()

  for line in file.lines:
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

proc parseCmd(s: string, c: Context): string =
  if s.startsWith "e.":
    getEnv s[2..^1]
  elif s.startsWith "e:":
    strip execProcess strip s[2..^1]
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

proc renderFile(file: string, c: Context): string =
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


proc writeHelp =
  echo """
heh
"""

proc writeVersion =
  echo "v0.1.0"


var
  inFiles = newSeq[string]()
  outFiles = newSeq[string]()
  contextFiles = newSeq[string]()
  profileFile = ""
  context = newTable[string, string]()
  overrideContext = newTable[string, string]()

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
    of "help", "h":
      writeHelp()
      quit 0
    of "version", "v":
      writeVersion()
      quit 0
    else:
      abortWith &"Couldn't parse command line argument: {key}"
  of cmdEnd: discard

if inFiles.len != outFiles.len:
  abortWith "Input/output files mismatch"

for file in contextFiles:
  if file.existsFile:
    context.addContext file
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
