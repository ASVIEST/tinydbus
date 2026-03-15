## Live verification of spec quotes against the current upstream D-Bus
## specification. Requires -d:ssl.

import std/httpclient
import spec_quote

var client = newHttpClient()
let html = client.getContent("https://dbus.freedesktop.org/doc/dbus-specification.html")
client.close()

specQuoteSuite "spec quote verification (live)":
  html
