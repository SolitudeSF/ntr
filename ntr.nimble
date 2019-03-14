# Package

version       = "0.3.2"
author        = "SolitudeSF"
description   = "Nim templating rice/resolver"
license       = "MIT"
srcDir        = "src"
bin           = @["ntr"]

# Dependencies

requires "nim >= 0.19.0", "chroma >= 0.0.1", "cligen >= 0.9.19"

task man, "Render manpage with scdoc":
  exec "scdoc < ntr.1.scd > ntr.1"
