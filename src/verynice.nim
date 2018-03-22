import strutils, sequtils, tables, ospaths, osproc, parseopt

type
  Context = TableRef[string, string]

const
  varOpen = "{{"
  varClose = "}}"

proc leadWhite(s: string): int =
  for c in s:
    if c in Whitespace: inc result else: break


proc getContext*(file: string): Context =
  result = newTable[string, string]()
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
        result.add prefix & t[0].strip, t[1].strip


proc parseCmd*(s: string, c: Context): string =
  if s.startsWith "e.":
    getEnv s[2..^1]
  elif s.startsWith "e:":
    strip execProcess strip s[2..^1]
  elif s in c:
    c[s]
  else: ""


proc render*(text: string, c: Context): string =
  result = text
  var
    idx = 0
    opens = newSeq[int]()

  while true:
    let idxOpen = text.find(varOpen, idx)
    if idxOpen > 0:
      idx = idxOpen + 2
      opens.add idxOpen
    else: break

  for i in countdown(opens.high, 0):
    let open = opens[i]
    let close = result.find(varClose, opens[i] + 2)
    if close > 0:
      result = result[0..<open] &
               result[open + 2..<close].strip.parseCmd(c) &
               result[close + 2..^1]

