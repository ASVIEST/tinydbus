## Offline verification of `# spec: "..."` and `# spec-table: "..."` comments
## against a vendored D-Bus specification HTML snapshot.

import std/os
import spec_quote

const specPath = currentSourcePath().parentDir / "dbus-specification-0.43.html"

specQuoteSuite "spec quote verification":
  readFile(specPath)
