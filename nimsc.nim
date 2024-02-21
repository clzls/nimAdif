import os

when not defined(nimscript):
  # Cheat LSP
  import system/nimscript

from strformat import fmt
task docs, "Builds documentation for the project":
  let na = thisDir() / srcDir / "nimAdif.nim"
  let outdir = thisDir() / "htmldocs"
  var cmd = fmt"doc --project --index:only --docInternal --outdir:{outdir} {na}"
  echo cmd
  selfExec cmd
  cmd = fmt"doc --project --docInternal --outdir:{outdir} {na}"
  echo cmd
  selfExec cmd
