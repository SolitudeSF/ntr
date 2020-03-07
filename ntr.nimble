# Package

version       = "0.4.0"
author        = "SolitudeSF"
description   = "Nim templating rice/resolver"
license       = "MIT"
srcDir        = "src"
bin           = @["ntr"]

# Dependencies

requires "nim >= 1.0.0", "chroma >= 0.1.0", "cligen >= 0.9.43"

task man, "Render manpage with scdoc":
  exec "scdoc < ntr.1.scd > ntr.1"
