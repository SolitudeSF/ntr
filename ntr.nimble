# Package

version       = "0.2.0"
author        = "SolitudeSF"
description   = "Nim templating rice/resolver"
license       = "MIT"
srcDir        = "src"
bin           = @["ntr"]

# Dependencies

requires "nim >= 0.18.1", "chroma"

task man, "Render manpage with scdoc":
  exec "scdoc < ntr.1.scd > ntr.1"
