import strutils, strformat, strtabs, os, osproc, sequtils, terminal
import imageman/colors, cligen

type Context = StringTableRef

const
  illegalChars = {'.', '{', '}', '<', '>', ':', '$', '|'} + Whitespace
  envPrefix = "NTR_"
  emptySet: set[char] = {}

proc abortWith(s: string, n = 1) = stderr.writeLine s; quit n

func newContext: Context = newStringTable()

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

proc renderFile(file: string, c = newContext()): string
proc render(text: string, c = newContext()): string

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
      prefix.setLen 0
      for pref in prefixes:
        prefix &= pref
        prefix &= '.'
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

proc addContextFile(c: var Context, file: string) =
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for t in file.lines:
    let line = t.render
    contextRoutine c

proc getContext(s: string): Context =
  result = newContext()
  var
    prefixes = newSeq[string]()
    prefix = ""
    pad = newSeq[int]()
  for t in s.splitLines:
    let line = t.render
    contextRoutine result

func parseHex(c: char): uint8 =
  result = uint8(
    case c
    of '0'..'9': c.ord - '0'.ord
    of 'a'..'f': 10 + c.ord - 'a'.ord
    of 'A'..'F': 10 + c.ord - 'A'.ord
    else: 0
  )

func parseColor(s: string, alpha, oct: bool): ColorRGBAU =
  let s = if oct: s[1..^1] else: s
  ColorRGBAU [
    s[0].parseHex * 16 + s[1].parseHex,
    s[2].parseHex * 16 + s[3].parseHex,
    s[4].parseHex * 16 + s[5].parseHex,
    if alpha: s[6].parseHex * 16 + s[7].parseHex
    else: 255
  ]

func toHexChar(u: uint8): char =
  case u
  of 0..9: chr(u + '0'.ord)
  of 10..15: chr(u - 10 + 'A'.ord)
  else: raise newException(ValueError, "Cant convert to character.")

func toHex(u: uint8): string =
  result = newString(2)
  result[0] = toHexChar(u div 16)
  result[1] = toHexChar(u mod 16)

func toHex(c: ColorRGBAU, alpha, oct: bool): string =
  if oct: result &= '#'
  result &= c.r.toHex
  result &= c.g.toHex
  result &= c.b.toHex
  if alpha: result &= c.a.toHex

func lighten(c: ColorRGBAU, a: float): ColorRGBAU =
  var hsl = c.toRGBF.toHSL
  hsl.l += a
  hsl.l = clamp(hsl.l, 0, 1)
  result = hsl.toRGBF.toRGBAF.toRGBAU
  result.a = c.a

func darken(c: ColorRGBAU, a: float): ColorRGBAU =
  c.lighten -a

func saturate(c: ColorRGBAU, a: float): ColorRGBAU =
  var hsl = c.toRGBF.toHSL
  hsl.s += a
  hsl.s = clamp(hsl.s, 0, 1)
  result = hsl.toRGBF.toRGBAF.toRGBAU
  result.a = c.a

func desaturate(c: ColorRGBAU, a: float): ColorRGBAU =
  c.saturate -a

template cmdColor(a): untyped =
  proc `cmd a`(c, v: string): string =
    try:
      let
        hasAlpha = c.len > 7
        hasOct = c[0] == '#'
      return c.parseColor(hasAlpha, hasOct).`a`(v.parseFloat).toHex(hasAlpha, hasOct)
    except ValueError:
      stderr.writeLine "Couldn't parse value: " & v

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

template renderRoutine(lines: untyped): untyped =
  for line in lines:
    var
      r = line
      i = line.high
      os = newSeq[int]()
    while i >= line.low:
      let o = r.rfind("<{", last = i)
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
    result &= r & "\p"
  result.setLen result.high

proc renderFile(file: string, c = newContext()): string =
  renderRoutine file.lines

proc renderStdin(c = newContext()): string =
  renderRoutine stdin.lines

proc render(text: string, c = newContext()): string =
  renderRoutine text.splitLines

proc parseProfile(file: string, i, o: var seq[string]) =
  for k, v in file.renderFile.getContext:
    i.add k
    o.add v

proc ntr(
  context_files: seq[string],
  profile = "",
  in_file: seq[string] = @[], out_file: seq[string] = @[],
  inplace: seq[string] = @[], override: seq[string] = @[],
  only_default = false, only_external = false,
  no_def_profile = false, no_def_context = false, no_def_finisher = false,
  allow_empty = false, force_empty = false,
  backup = false, finish = true
): int =
  ## Context files supplied as arguments and sourced from cwd or from ntrDirectory/contexts.
  ##
  ## If no profile or input files specified, input/output pairs are read from ntrDirectory/profile.
  ## Specifying both -d and -D negates both options.

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
    noDefProfile = noDefProfile
    onlyDefault = onlyDefault
    onlyExternal = onlyExternal
    inFiles = inFile
    outFiles = outFile
    context = newContext()
    overrideContext = newContext()

  if onlyDefault and onlyExternal:
    onlyDefault = false
    onlyExternal = false

  if profile.len > 0:
    if not onlyDefault and existsFile profile:
      parseProfile profile, inFiles, outFiles
    elif not onlyExternal and existsFile ntrProfiles / profile:
      parseProfile ntrProfiles / profile, inFiles, outFiles
    else:
      abortWith &"File `{profile}` does not exist"

  if inFiles.len != outFiles.len:
    abortWith "Input/output files mismatch"

  for file in inplace:
    inFiles.add file
    outFiles.add file

  if not forceEmpty:
    if not noDefContext and not onlyExternal and existsFile ntrDefContext:
      context.addContextFile ntrDefContext

    for file in contextFiles:
      if not onlyDefault and existsFile file:
        context.addContextFile file
      elif not onlyExternal and existsFile ntrContexts / file:
        context.addContextFile ntrContexts / file
      else:
        abortWith &"File `{file}` does not exist"

    for s in override:
      let splits = s.split(':', 1)
      if splits.len == 2:
        context.parseId splits[0], splits[1]
      else:
        abortWith &"Incorrect override: {splits[0]}"

  if not (allowEmpty or forceEmpty) and context.len == 0:
    abortWith "Empty context"

  if not stdin.isatty:
    noDefProfile = true
    echo renderStdin context

  if not noDefProfile and inFiles.len == 0 and ntrDefProfile.existsFile:
    ntrDefProfile.parseProfile inFiles, outFiles

  for n, file in inFiles:
    var output = ""
    if not onlyDefault and existsFile file:
      output = file.renderFile context
    elif not onlyExternal and existsFile ntrTemplates / file:
      output = (ntrTemplates / file).renderFile context
    else:
      abortWith &"File `{file}` does not exist"
    let outfile = outFiles[n]
    if outfile == "-":
      echo output
    else:
      let dir = parentDir outfile
      if backup and existsFile outfile:
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

  if finish:
    for i in inFiles:
      let f = ntrFinishers / i.extractFilename
      if existsFile f:
        try:
          let errC = execCmd f
          if errC != 0:
            stderr.writeLine &"Finisher `{f}` exited with {errC}"
        except:
          stderr.writeLine &"Couldn't run finisher `{f}`"
    if not noDefFinisher and existsFile ntrDefFinisher:
      try:
        let errC = execCmd ntrDefFinisher
        if errC != 0:
          stderr.writeLine &"Default finisher exited with {errC}"
      except:
        stderr.writeLine &"Couldn't run default finisher"

clCfg.version = "0.4.0"
dispatch ntr,
  short = {"in_file": 'i', "out_file": 'o', "inplace": 'I', "profile": 'p',
    "allow_empty": 'e', "force_empty": 'E', "only_default": 'd',
    "only_external": 'D', "no_def_context": 'C', "no_def_finisher": 'F',
    "no_def_profile": 'P', "finish": 'f', "override": 'O', "version": 'v'},
  help = {
    "in_file": "add input file from pwd or from ntrDirectory/templates",
    "inplace": "add input file and modify it in-place",
    "out_file": "add output file",
    "profile": "specify profile file",
    "no_def_context": "disable default context",
    "no_def_profile": "disable default profile",
    "no_def_finisher": "disable default finisher",
    "allow_empty": "don't abort on empty context",
    "force_empty": "force empty context",
    "finish": "enable/disable execution of finishers",
    "only_default": "only use files from ntrDirectory",
    "only_external": "never use files from ntrDirectory",
    "override": "specify context addition/overrides",
    "backup": "backup existing files"
  }
