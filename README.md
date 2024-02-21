# nimAdif
An Amateur Data Interchange Format (ADIF) formatter and parser library written purely in Nim.

It contains only a simple formatter in `0.1.x`. Parser would be implemented in later version.

## Build

### Using the library

Add `requires` directive in your `.nimble` file:
```nim
requires "nimAdif ~= 0.1.0"
```

And `import` and use it in your code:
```nim
import nimAdif

var record = AdifLogRecord()
record.call = "BI1MHK"
record.freq = 438_500_000

let log = result.dumps()
```

### Build Document

```
nimble docs
```

Default directory for docs are `htmldocs/`.
You may change it in `nimsc.nim`.
