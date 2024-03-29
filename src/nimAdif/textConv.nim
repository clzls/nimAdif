import std / [strutils, times]


func getDateStrCompact*(dt: DateTime): string =
  ## Gets the current local date as a string of the format `YYYYMMDD`.
  runnableExamples:
    import std/times
    echo getDateStrCompact(now() - 1.months)
  result = newStringOfCap(8)  # len("YYYYMMDD") == 8
  result.addInt dt.year
  result.add intToStr(cast[int](dt.month), 2)
  result.add intToStr(dt.monthday, 2)


func getTimeStrCompact*(dt: DateTime): string =
  ## Gets the current local time as a string of the format `HHMMSS`.
  runnableExamples:
    import std/times
    echo getTimeStrCompact(now())
  result = newStringOfCap(6)  # len("HHMMSS") == 6
  result.add intToStr(dt.hour, 2)
  result.add intToStr(dt.minute, 2)
  result.add intToStr(dt.second, 2)

proc parseInt*(s: char): int =
  if s notin '0'..'9':
    raise newException(ValueError, "invalid integer: " & s)
  return s.ord - '0'.ord

proc parseIntOrDefault*(s: char; default: int = 0): int =
  if s notin '0'..'9':
    default
  else:
    s.ord - '0'.ord

