## Hacks for _`std/tables`.
## 

import std/importutils
import std/tables {.all.}
import std/hashes

# Hack to avoid dirty tricks leaking
import std/tables as tab2
export tab2


template withValue*[A, B](t: var OrderedTable[A, B], key: A, value, body: untyped) =
  ## Retrieves the value at `t[key]`.
  ##
  ## `value` can be modified in the scope of the `withValue` call.
  runnableExamples:
    type
      User = object
        name: string
        uid: int

    var t = initOrderedTable[int, User]()
    let u = User(name: "Hello", uid: 99)
    t[1] = u

    t.withValue(1, value):
      # block is executed only if `key` in `t`
      value.name = "Nim"
      value.uid = 1314

    t.withValue(2, value):
      value.name = "No"
      value.uid = 521

    assert t[1].name == "Nim"
    assert t[1].uid == 1314

  mixin rawGet
  var hc: Hash
  var index = rawGet(t, key, hc)
  let hasKey = index >= 0
  privateAccess(t.type)
  if hasKey:
    var value {.inject.} = addr(t.data[index].val)
    body

template withValue*[A, B](t: var OrderedTable[A, B], key: A,
                          value, body1, body2: untyped) =
  ## Retrieves the value at `t[key]`.
  ##
  ## `value` can be modified in the scope of the `withValue` call.
  runnableExamples:
    type
      User = object
        name: string
        uid: int

    var t = initOrderedTable[int, User]()
    let u = User(name: "Hello", uid: 99)
    t[1] = u

    t.withValue(1, value):
      # block is executed only if `key` in `t`
      value.name = "Nim"
      value.uid = 1314

    t.withValue(521, value):
      doAssert false
    do:
      # block is executed when `key` not in `t`
      t[1314] = User(name: "exist", uid: 521)

    assert t[1].name == "Nim"
    assert t[1].uid == 1314
    assert t[1314].name == "exist"
    assert t[1314].uid == 521

  mixin rawGet
  var hc: Hash
  var index = rawGet(t, key, hc)
  let hasKey = index >= 0
  privateAccess(t.type)
  if hasKey:
    var value {.inject.} = addr(t.data[index].val)
    body1
  else:
    body2
