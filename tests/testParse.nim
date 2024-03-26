# To run these tests, simply execute `nimble test`.

import std/[streams, wrapnils]
import unittest

import nimAdif/[parseadif, formatter]
import nimAdif/stdExt/tables

test "No headers":
  var strm = newStringStream("<CalL:3>B1A<EOR>")
  var parser: AdifParser
  parser.open(strm, "tmp.adi")
  check parser.readRecord()
  check not ?.parser.rec.spec.isNil
  check "CALL" in parser.rec.spec
  check parser.rec.getStr("CALL") == "B1A"

  check parser.readRecord() == false
  check parser.rec.isNil
  check parser.readRecord() == false
  check parser.rec.isNil

  parser.close()
  strm.close()

test "With headers":
  var strm = newStringStream("Haha\c\l<adif_ver:5>3.0.5<EOH>\c\l<CalL:3>B1A<EOR>")
  var parser: AdifParser
  parser.open(strm, "tmp.adi")
  parser.readHeader()
  check not ?.parser.headers.spec.isNil
  check parser.headers.header == "Haha\c\l"
  check "ADIF_VER" in parser.headers.spec
  check parser.headers.getStr("ADIF_VER") == "3.0.5"
  check parser.readRecord()
  check not ?.parser.rec.spec.isNil
  check "CALL" in parser.rec.spec
  check parser.rec.getStr("CALL") == "B1A"

  check parser.readRecord() == false
  check parser.rec.isNil

  parser.close()
  strm.close()
