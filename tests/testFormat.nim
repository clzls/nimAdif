# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import nimAdif
test "Generate raw K-V pairs":
  check rawKvPair("CALL", "BI1MHK") == "<CALL:6>BI1MHK"
  check rawKvPair("CALL", "BI1MHK", "S") == "<CALL:6:S>BI1MHK"
