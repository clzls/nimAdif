import std / [segfaults, times]
import std / with


import ./stdExt / [tables]
import ./ [textConv]

type
  EBand* {.pure.} = enum
    e6m = "6m"
    e2m = "2m"
    e70cm = "70cm"
    eOOB = "OOB"
  EItemType* {.pure.} = enum
    iStr, iMultiStr, iNumberRaw, iEnumRaw,
    iNumber, iInt,
    iRaw,


type
  AdifLogSpecifierObj* = object ## ADI Data-Specifier
    key: string
    val: string
    case kind*: EItemType
    of iStr, iMultiStr, iNumberRaw, iEnumRaw:
      discard
    of iNumber:
      numF: BiggestFloat
    of iInt:
      numI: BiggestInt
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


const
  tabBandRange: array[EBand, Slice[int]] = [
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
