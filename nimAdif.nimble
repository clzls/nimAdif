# Package

version       = "0.1.1"
author        = "clzls"
description   = "An Amateur Data Interchange Format (ADIF) formatter and parser library written purely in Nim."
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.2"

# Additional tools
when withDir(thisDir(), system.fileExists("nimsc.nim")):
  include "nimsc.nim"
