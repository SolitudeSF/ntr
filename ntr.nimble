# Package

version       = "0.1.8"
author        = "SolitudeSF"
description   = "Nim templating rice/resolver"
license       = "MIT"
srcDir        = "src"
bin           = @["ntr"]

# Dependencies

requires "nim >= 0.18.0"

task asciidoc, "Render manpage with asciidoc":
  exec "a2x -f manpage ntr.1.asciidoc"

task pandoc, "Render manpage with pandoc":
  exec "pandoc -s -t man ntr.1.md -o ntr.1"
