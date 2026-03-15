# tinydbus
Tiny pure nim dbus implementation. Heavily inspired by https://github.com/vincenthz/udbus for C,
but tinydbus is smaller yet more feature-rich, including support for big-endian, compiletime intercepts etc.

## Installation
via atlas:
```sh
atlas use https://github.com/ASVIEST/tinydbus
```
via nimble:
```sh
nimble install https://github.com/ASVIEST/tinydbus
```

## Quickstart
```nim
import pkg/tinydbus

let (conn, _) = openSessionBus()
defer: conn.close()

let msg = initMethodCallMsg(
  "org.freedesktop.Notifications",
  "/org/freedesktop/Notifications",
  "org.freedesktop.Notifications",
  "Notify")

var body = initBodyBuilder()
body.add "myapp"          # app_name
body.add 0'u32            # replaces_id
body.add ""               # app_icon
body.add "Hello!"         # summary
body.add "From tinydbus"  # body

let actions = body.addArrayBegin("s")
actions.finish()
let hints = body.addArrayBegin("{sv}")
hints.finish()

body.add -1'i32           # expire_timeout

msg.setBody(body)

let reply = conn.call(msg)
var br = initBodyReader(reply.body, reply.signature)
echo "Notification id: ", br.read[:uint32]()
```

### Compile-time intercepts
tinydbus supports compile-time registration of intercept handlers. When `call` is used, registered intercepts are checked first — if a match is found, the handler uses bounded proc. This enables external projects to provide fake D-Bus services (e.g. for Windows cross-compilation).

```nim
import pkg/tinydbus

proc handleRead(msg: Message): Message =
  result = initMethodReturnMsg(msg)
  var body = initBodyBuilder()
  body.addVariant("u") do (b: var BodyBuilder):
    b.add 1'u32  # dark theme
  result.setBody(body)

addIntercept(
  "org.freedesktop.portal.Settings",
  "/org/freedesktop/portal/desktop",
  "org.freedesktop.portal.Settings",
  "Read",
  handleRead)
```

Use empty string as a wildcard for any field:

```nim
import pkg/tinydbus

proc catchAllHandler(msg: Message): Message = ...

# Intercept all methods on this interface
addIntercept(
  "org.freedesktop.portal.Settings",
  "",  # any path
  "",  # any interface
  "",  # any method
  catchAllHandler)
```

# flags:
`-d:tinydbus.runtimeDispatch`: when this flag is enabled, interceptors declared after the `proc` will work. This means you can create a `proc` that uses a `call` and add interceptors after it; without this flag, you would have to use a `template` instead of a `proc`. The downside is the added realtime overhead due to calling the `proc` by address.

`-d:tinydbus.disableValidation`: disables validation layer, it makes tinydbus faster. The validation layer causes a significant slowdown. It is recommended to disable it for release builds if you need performance (15-25% without request batching and up to 25-34% with batching). In a synthetic test without real requests, the code slows down by up to 12 times. However, the validation layer is enabled by default because it makes the code safer, and the performance loss is not that significant considering that IPC round-trip takes most of the time.
