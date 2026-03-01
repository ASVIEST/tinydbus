## send a desktop notification via org.freedesktop.Notifications.

import tinydbus

proc main() =
  let (conn, _) = openSessionBus()
  defer: conn.close()

  let msg = initMethodCallMsg(
    "org.freedesktop.Notifications",
    "/org/freedesktop/Notifications",
    "org.freedesktop.Notifications",
    "Notify"
  )

  var body = initBodyBuilder()
  body.add "tinydbus"       # app_name
  body.add 0                # replaces_id
  body.add ""               # app_icon
  body.add "Hello!"         # summary
  body.add "Sent from tinydbus example" # body

  let actions = body.addArrayBegin("s") # empty array of strings
  actions.finish()
  let hints = body.addArrayBegin("{sv}") # empty dict
  hints.finish()

  body.add -1 # expire_timeout (-1 = default)

  msg.setBody(body)

  let reply = conn.call(msg)
  var br = initBodyReader(reply.body, reply.signature)
  echo "Notification id: ", br.read[:uint32]()

main()
