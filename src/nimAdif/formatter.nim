import std / [segfaults, times]
import std / with


import ./stdExt / [tables]
import ./ [textConv]

type
  EBand* {.pure.} = enum
    e40m = "40m"
    e30m = "30m"
    e20m = "20m"
    e17m = "17m"
    e15m = "15m"
    e12m = "12m"
    e10m = "10m"
    e6m = "6m"
    e2m = "2m"
    e70cm = "70cm"
    eOOB = "OOB"
  EItemType* {.pure.} = enum
    iStr, iMultiStr, iNumberRaw, iEnumRaw,
    iNumber, iInt, iBool,
    iRaw,


type
  AdifLogSpecifierObj* = object ## ADI Data-Specifier
    key*: string
    val: string
    case kind*: EItemType
    of iStr, iMultiStr, iNumberRaw, iEnumRaw:
      discard
    of iNumber:
      numF: BiggestFloat
    of iInt:
      numI: BiggestInt
    of iBool:
      numB: bool
    of iRaw:
      tyCode: string
  AdifLogSpecifier* = ref AdifLogSpecifierObj
  AdifLogHeader* = ref object ## ADI Header
    header*: string
    spec*: TableRef[string, AdifLogSpecifier] = newTable[string, AdifLogSpecifier]()
  AdifLogRecord* = ref object ## ADI Record
    rejected*: bool = false # Rejected by some filters?
    spec*: TableRef[string, AdifLogSpecifier] = newTable[string, AdifLogSpecifier]()
  AdifLogFile* = ref object ## ADI File
    header: string
    record*: seq[AdifLogRecord]


# Errors
type
  AdifError* = object of IOError ## An exception that is raised if
                                 ## a parsing or formatting error occurs.


const
  tabBandRange: array[EBand, Slice[int]] = [
    e40m: 7_000_000..7_300_000,
    e30m: 10_100_000..10_150_000,
    e20m: 14_000_000..14_350_000,
    e17m: 18_068_000..18_168_000,
    e15m: 21_000_000..21_450_000,
    e12m: 24_890_000..24_990_000,
    e10m: 28_000_000..29_700_000,
    e6m: 50_000_000..54_000_000,
    e2m: 144_000_000..148_000_000,
    e70cm: 420_000_000..450_000_000,
    eOOB: 0..0,
  ]
  strEoh = "<EOH>"
  strEor = "<EOR>"
  estimSpeciLen = 20
  estimRecLen = estimSpeciLen * 10
  estimOverhead = 10


func getBand*(freqHz: int): EBand =
  # TODO: Use binary search instead
  for i, x in tabBandRange.pairs:
    if freqHz in x:
      return i
  return eOOB


func rawKvPair*(key, val: string): string =
  runnableExamples:
    assert rawKvPair("CALL", "BI1MHK") == "<CALL:6>BI1MHK"
  result = newStringOfCap(val.len + key.len + 10)
  with result:
    add('<')
    add(key)
    add(':')
    addInt(val.len)
    add('>')
    add(val)

func rawKvPair*(key, val, typ: string): string =
  runnableExamples:
    assert rawKvPair("CALL", "BI1MHK", "S") == "<CALL:6:S>BI1MHK"
  result = newStringOfCap(val.len + key.len + 10)
  with result:
    add('<')
    add(key)
    add(':')
    addInt(val.len)
    add(':')
    add(typ)
    add('>')
    add(val)


# Public APIs - IO

func dumps*(self: AdifLogSpecifier): string =
  ## Dumps a ADI Data-Specifier to string.
  runnableExamples:
    let k = newAdifLogSpecifierStr("CALL", "BI1MHK")
    assert k.dumps() == "<CALL:6>BI1MHK"
  result = newStringOfCap(estimSpeciLen)
  if self.isNil: return
  # TODO: type descriptors...
  result.add rawKvPair(self.key, self.val)

func dumps*(self: AdifLogRecord): string =
  ## Dumps a ADI Record to string.
  result = newStringOfCap(self.spec.len * estimSpeciLen + estimOverhead)
  if self.isNil: return
  if self.rejected: return
  for x in self.spec.values:
    result.add x.dumps
  if result.len != 0:
    result.add strEor

func dumps*(self: AdifLogHeader): string =
  ## Dumps a ADI Header to string.
  runnableExamples:
    let k = newAdifLogSpecifierStr("adif_ver", "3.1.4")
    let p = new AdifLogHeader
    p.header = "Hello!"
    p.add k
    echo p.dumps()
    assert p.dumps() == "Hello!<adif_ver:5>3.1.4<EOH>"
  result = newStringOfCap(self.header.len + self.spec.len * estimSpeciLen + estimOverhead)
  if self.isNil: return
  result.add self.header
  for x in self.spec.values:
    result.add x.dumps
  if result.len != 0:
    result.add strEoh

func dumps*(self: AdifLogFile): string =
  ## Dumps a ADI File to string.
  result = newStringOfCap(self.header.len + self.record.len * estimRecLen + estimOverhead)
  if self.isNil: return
  result.add self.header
  for x in self.record:
    result.add x.dumps
    result.add '\n'


iterator dumps*(self: AdifLogFile): string =
  ## Dumps a ADI File to string, iterating through each record.
  yield self.header
  for x in self.record:
    yield x.dumps


# Public APIs - setters

func newAdifLogSpecifierStr*(key, val: string): AdifLogSpecifier =
  AdifLogSpecifier(key: key, val: val, kind: iStr)

func newAdifLogSpecifierBool*(key: string; bval: bool): AdifLogSpecifier =
  AdifLogSpecifier(key: key, val: (if bval: "Y" else: "N"), kind: iBool, numB: bval)

proc newAdifLogSpecifierNumRaw*(key, val: string): AdifLogSpecifier =
  AdifLogSpecifier(key: key, val: val, kind: iNumberRaw)

proc newAdifLogSpecifierBand*(key: string; val: EBand): AdifLogSpecifier =
  AdifLogSpecifier(key: key, val: $val, kind: iEnumRaw)

proc newAdifLogSpecifierFreq*(key: string; valHz: int): AdifLogSpecifier =
  ## Create a ADI Data-Specifier for frequencies.
  runnableExamples:
    let k = newAdifLogSpecifierFreq("FREQ", 438500000)
    assert k.dumps() == "<FREQ:5>438.5"
  #newAdifLogSpecifierNumRaw(key, "".dup(addFloatRoundtrip(valHz.toBiggestFloat / 1e6)))
  newAdifLogSpecifierNumRaw(key, $(valHz.toBiggestFloat / 1e6))

func newAdifLogSpecifierRaw*(key, val, tyCode: string): AdifLogSpecifier =
  AdifLogSpecifier(key: key, val: val, kind: iRaw, tyCode: tyCode)


func add*(self: AdifLogRecord or AdifLogHeader; itm: AdifLogSpecifier) =
  if self.isNil: raise newException(ValueError, "`self` is nil")
  if self.spec.isNil:
    self.spec = newTable[string, AdifLogSpecifier]()
  self.spec[itm.key] = itm

func header*(self: AdifLogFile): string {.inline.} =
  if self.isNil: "" else: self.header

func getStr*(self: AdifLogSpecifier): string {.inline.} =
  if self.isNil: "" else: self.val

func `header=`*(self: AdifLogFile; hrd: AdifLogHeader) {.inline.} =
  if self.isNil: raise newException(ValueError, "`self` is nil")
  self.header = hrd.dumps
  if self.header.len > 0 and self.header[^1] != '\n':
     self.header.add '\n'

proc `[]=`*(self: AdifLogRecord or AdifLogHeader; key, val: string) =
  ## Add a string quickly
  if self.isNil: raise newException(ValueError, "`self` is nil")
  if unlikely(self.spec.isNil):
    self.spec = newTable[string, AdifLogSpecifier]()
  self.spec[key] = newAdifLogSpecifierStr(key, val)

proc `[]=`*(self: AdifLogRecord or AdifLogHeader; key: string; bval: bool) =
  ## Add a string quickly
  if self.isNil: raise newException(ValueError, "`self` is nil")
  if unlikely(self.spec.isNil):
    self.spec = newTable[string, AdifLogSpecifier]()
  self.spec[key] = newAdifLogSpecifierBool(key, bval)

proc getStr*(self: AdifLogRecord or AdifLogHeader; key: string): string =
  ## Get as string quickly
  if self.isNil: raise newException(AdifError, "`self` is nil")
  if unlikely(self.spec.isNil):
    raise newException(AdifError, "`self.spec` is nil")
  if key notin self.spec:
    raise newException(AdifError, "`key not found")
  self.spec[key].val

proc getStrOrDefault*(self: AdifLogRecord or AdifLogHeader; key, default: string): string =
  ## Get as string quickly
  if self.isNil: return default
  if unlikely(self.spec.isNil):
    return default
  if key notin self.spec:
    return default
  return self.spec[key].val

proc `call=`*(self: AdifLogRecord; call: string) {.inline.} =
  self["CALL"] = call

proc `stationCall=`*(self: AdifLogRecord; call: string) {.inline.} =
  self["STATION_CALLSIGN"] = call

proc `freq=`*(self: AdifLogRecord; freq: int) {.inline.} =
  self.add newAdifLogSpecifierBand("BAND", freq.getBand)
  self.add newAdifLogSpecifierFreq("FREQ", freq)

proc `freqRx=`*(self: AdifLogRecord; freq: int) {.inline.} =
  self.add newAdifLogSpecifierBand("BAND_RX", freq.getBand)
  self.add newAdifLogSpecifierFreq("FREQ_RX", freq)

proc `timeOn=`*(self: AdifLogRecord; dt: DateTime) {.inline.} =
  if self.isNil: raise newException(ValueError, "`self` is nil")
  let dtZ = dt.utc()
  self.add newAdifLogSpecifierRaw("QSO_DATE", dtZ.getDateStrCompact, "D")
  self.add newAdifLogSpecifierRaw("TIME_ON", dtZ.getTimeStrCompact, "T")

proc `timeOff=`*(self: AdifLogRecord; dt: DateTime) {.inline.} =
  if self.isNil: raise newException(ValueError, "`self` is nil")
  let dtZ = dt.utc()
  let j = dtZ.getDateStrCompact
  if "QSO_DATE" in self.spec and self.spec["QSO_DATE"].val == j:
    # Although omitting "QSO_DATE_OFF" for QSOs within 24 hours is permitted,
    # we still provide it if `QSO_DATE_OFF != QSO_DATE`.
    discard
  else:
    self.add newAdifLogSpecifierRaw("QSO_DATE_OFF", j, "D")
  self.add newAdifLogSpecifierRaw("TIME_OFF", dtZ.getTimeStrCompact, "T")
