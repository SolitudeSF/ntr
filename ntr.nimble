# Package

version       = "0.1.9"
author        = "SolitudeSF"
description   = "Nim templating rice/resolver"
license       = "MIT"
srcDir        = "src"
bin           = @["ntr"]

# Dependencies

requires "nim >= 0.18.0"

task man, "Render manpage with scdoc":
  exec "scdoc < ntr.1.scd > ntr.1"
