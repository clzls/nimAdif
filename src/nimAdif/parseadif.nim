## This module implements a simple ADIF parser.
##
## Basic usage
## ===========
##
## .. code-block:: nim
##   import nimAdif
##   import nimAdif/parseadif
##   from std/os import paramStr
##   from std/streams import newFileStream
##
##   var s = newFileStream(paramStr(1), fmRead)
##   if s == nil:
##     quit("cannot open the file" & paramStr(1))
##
##   var x: AdifParser
##   open(x, s, paramStr(1))
##   while readRecord(x):
##     echo "new record: "
##     echo dumps(x.rec)
##   close(x)
##
## For ADIF files with a header, the header can be read:
##
## .. code-block:: nim
##   import nimAdif
##   import nimAdif/parseadif
##
##   # Prepare a file
##   let content = """Test ADIF file
##   <adif_ver:5>3.1.4
##   <EOH>
##   <call:6>WN4AZY<band:3>20M<mode:4>RTTY<qso_date:8>19960513
##   <time_on:4>1305<eor>
##   """
##   writeFile("temp.adi", content)
##
##   var p: AdifParser
##   p.open("temp.adi")
##   p.readHeader()
##   echo dumps(p.headers)
##   while p.readRecord():
##     echo "new row: "
##     echo dumps(p.rec)
##   p.close()
##

import strutils
import lexbase, streams

when defined(nimPreviewSlimSystem):
  import std/syncio

import ./[textConv, formatter]
import ./stdExt/tables

export formatter

type
  AdifParser* = object of BaseLexer ## The parser object.
                                   ##
                                   ## It consists of two public fields:
                                   ## * `rec` is the current record
                                   ## * `headers` are the headers that are defined in the ADIF file
                                   ##   (read using `readHeader <#readHeader,AdifParser>`_).
    rec*: AdifLogRecord
    filename: string
    norm: bool
    currRec: int
    headers*: AdifLogHeader

type
  EParseSpecResl = enum
    failed, normal, eoh, eor,
    unkFlag, # Unknown flags without valid data length field, seen in some programs

const
  maxiDataLen* = 20000 ## Maximum data length allowed in a field. Avoid buffer overflow attacks.
  maxiDataLenDiv10 = maxiDataLen div 10 ## Maximum data length allowed in a field divided by 10.

static:
  doAssert maxiDataLen < high(int) div 10 and maxiDataLen > 0

proc raiseEInvalidAdif(filename: string, line, col: int,
                      msg: string) {.noreturn.} =
  var e: ref AdifError
  new(e)
  if filename.len == 0:
    e.msg = "Error: " & msg
  else:
    e.msg = filename & "(" & $line & ", " & $col & ") Error: " & msg
  raise e

proc error(self: AdifParser, pos: int, msg: string) =
  raiseEInvalidAdif(self.filename, self.lineNumber, getColNumber(self, pos), msg)

proc open*(self: var AdifParser, input: Stream, filename: string; normalize: bool = true) =
  ## Initializes the parser with an input stream. `Filename` is only used
  ## for nice error messages. The parser's behaviour can be controlled by
  ## the diverse optional parameters:
  ## - `normalize`: normalize keys to upper-cases.
  ##
  ## See also:
  ## * `open proc <#open,AdifParser,string,char,char,char>`_ which creates the
  ##   file stream for you
  runnableExamples:
    import std/streams
    var strm = newStringStream("Test, test\n<CALL:3>B1A<EOR>")
    var parser: AdifParser
    parser.open(strm, "tmp.adi")
    parser.close()
    strm.close()

  lexbase.open(self, input)
  self.filename = filename
  self.norm = normalize

proc open*(self: var AdifParser, filename: string; normalize: bool = true) =
  ## Similar to the `other open proc<#open,AdifParser,Stream,string,char,char,char>`_,
  ## but creates the file stream for you.
  runnableExamples:
    from std/os import removeFile
    writeFile("tmp.adi", "Test, test\n<CALL:3>B1A<EOR>")
    var parser: AdifParser
    parser.open("tmp.adi")
    parser.close()
    removeFile("tmp.adi")

  var s = newFileStream(filename, fmRead)
  if s == nil: self.error(0, "cannot open: " & filename)
  open(self, s, filename, normalize)

proc parseField(self: var AdifParser, a: var AdifLogSpecifier): EParseSpecResl =
  while true:
    case self.buf[self.bufpos]
    of '<': break
    of '\c': self.bufpos = handleCR(self, self.bufpos)
    of '\l': self.bufpos = handleLF(self, self.bufpos)
    of EndOfFile: return failed
    else: inc(self.bufpos)
  assert self.buf[self.bufpos] == '<'
  inc(self.bufpos)
  var
    key: string = newStringOfCap(32)
    dataLen: int = 0
    colonCnt: int = 0
    digi: int = -1
  while true:
    case self.buf[self.bufpos]
    of '>':
      inc(self.bufpos)
      break
    of ':':
      inc(colonCnt)
      inc(self.bufpos)
    of '\c': self.bufpos = handleCR(self, self.bufpos)
    of '\l': self.bufpos = handleLF(self, self.bufpos)
    of EndOfFile:
      error(self, self.bufpos, "Unexpected EOF!")
    else:
      case colonCnt
      of 0:
        add(key, self.buf[self.bufpos])
      of 1:
        # Length; Try to parse on the fly; allow leading zeros
        digi = parseIntOrDefault(self.buf[self.bufpos], -1)
        if digi < 0:
          error(self, self.bufpos, "Cannot parse field's length!")
        if dataLen > maxiDataLenDiv10:
          error(self, self.bufpos, "Cannot parse field's length: possibly overflow!")
        dataLen = dataLen * 10 + digi
      else:
        # Data type indicator `T`; Ignore type for now
        discard
      inc(self.bufpos)
  if colonCnt == 0:
    if key.len == 3:
      # 记录结束
      let p = key.toUpperAscii
      if not p.startsWith("EO"): return unkFlag
      case p[2]
      of 'R': return eor
      of 'H': return eoh
      else: return unkFlag
    error(self, self.bufpos, "Cannot parse field's key and length!")
  if key.len == 0:
    error(self, self.bufpos, "Cannot parse field's key!")
  if self.norm:
    key = key.toUpperAscii
  # Obtain data
  var
    dataBuf = newStringOfCap(dataLen)
  while dataBuf.len < dataLen:
    case self.buf[self.bufpos]
    of '\c':
      self.bufpos = handleCR(self, self.bufpos)
      dataBuf.add "\c\l"
    of '\l':
      self.bufpos = handleLF(self, self.bufpos)
      dataBuf.add "\c\l"
    of EndOfFile: return failed
    else:
      dataBuf.add self.buf[self.bufpos]
      inc(self.bufpos)
  a = newAdifLogSpecifierStr(key, dataBuf)
  return normal


proc processedRecords*(self: var AdifParser): int {.inline.} =
  ## Returns number of the processed records.
  ##
  ## But even if `readRecord <#readRecord,AdifParser,int>`_ arrived at EOF then
  ## processed record counter is incremented.
  runnableExamples:
    import std/streams

    var strm = newStringStream("Test, test\n<CALL:3>B1A<EOR>")
    var parser: AdifParser
    parser.open(strm, "tmp.adi")
    doAssert parser.readRecord()
    doAssert parser.processedRecords() == 1
    ## Even if `readRecord` arrived at EOF then `processedRecords` is incremented.
    doAssert parser.readRecord() == false
    doAssert parser.processedRecords() == 2
    doAssert parser.readRecord() == false
    doAssert parser.processedRecords() == 3
    parser.close()
    strm.close()

  self.currRec

proc readRecord*(self: var AdifParser): bool =
  ## Reads the next record. Returns false if the end of the file or unknown
  ## token has been encountered else true.
  runnableExamples:
    import std/streams
    var strm = newStringStream("<CALL:3>B1A<EOR>")
    var parser: AdifParser
    parser.open(strm, "tmp.adi")
    doAssert parser.readRecord()
    doAssert parser.rec.getStr("CALL") == "B1A"

    var emptySeq: seq[string]
    doAssert parser.readRecord() == false
    doAssert parser.rec == nil
    doAssert parser.readRecord() == false
    doAssert parser.rec == nil

    parser.close()
    strm.close()

  if self.rec.isNil:
    self.rec.reset()
    self.rec.new()
  # Reset other fields
  self.rec.rejected = false
  if self.rec.spec.isNil:
    self.rec.spec.new()
  else:
    self.rec.spec.clear()
  while self.buf[self.bufpos] != '\0':
    var recPending: AdifLogSpecifier
    case parseField(self, recPending)
    of failed, eoh:
      result = false
      break
    of unkFlag:
      # Ignore the flag and continue
      discard
    of eor:
      # finish this record
      break
    of normal:
      # Save this spec
      result = true
      self.rec.add(recPending)

  if not result:
    # Reset to nil
    self.rec.reset()
  inc(self.currRec)

proc close*(self: var AdifParser) {.inline.} =
  ## Closes the parser `self` and its associated input stream.
  lexbase.close(self)

proc readHeader*(self: var AdifParser) =
  ## Reads and parse the header.
  runnableExamples:
    import std/streams

    var strm = newStringStream("Test, test<EOH>\n<CALL:3>B1A<EOR>")
    var parser: AdifParser
    parser.open(strm, "tmp.adi")

    parser.readHeader()
    doAssert parser.headers.header == "Test, test"

    doAssert parser.readRecord()
    doAssert parser.rec.getStr("CALL") == "B1A"

    parser.close()
    strm.close()

  if self.buf[self.bufpos] == '<':
    # Per ADIF-spec, no header.
    self.headers = nil
    return
  if self.headers.isNil:
    self.headers.new()
  setLen(self.headers.header, 0)
  while true:
    case self.buf[self.bufpos]
    of '<': break
    of EndOfFile:
      # No record, exit
      return
    of '\c':
      self.bufpos = handleCR(self, self.bufpos)
      self.headers.header.add "\c\l"
    of '\l':
      self.bufpos = handleLF(self, self.bufpos)
      self.headers.header.add "\c\l"
    else:
      self.headers.header.add self.buf[self.bufpos]
      inc(self.bufpos)
  while self.buf[self.bufpos] != '\0':
    var recPending: AdifLogSpecifier
    case parseField(self, recPending)
    of failed, eor:
      break
    of unkFlag:
      # Ignore the flag and continue
      discard
    of eoh:
      # finish this header
      break
    of normal:
      # Save this spec
      self.headers.add(recPending)
