import pkg/tinydbus
import pkg/unittest2

suite "intercept cross-scope":
  test "cross-scope gensym call":
    proc fakeHandler(msg: Message): Message =
      result = initMethodReturnMsg(msg)
      var body = initBodyBuilder()
      body.add 100'u32
      result.setBody(body)

    block scope1:
      addIntercept("org.test.CrossScope",
                  "/org/test/Obj",
                  "org.test.Iface",
                  "Method",
                  fakeHandler)

      let msg = initMethodCallMsg(
        "org.test.CrossScope",
        "/org/test/Obj",
        "org.test.Iface",
        "Method")
      msg.serial = 1
      msg.sender = ":1.0"

      var conn: BusConnection
      let reply = conn.call(msg)

      check reply.kind == mtMethodReturn
      var br = initBodyReader(reply.body, reply.signature)
      check br.read[:uint32]() == 100'u32

    block scope2:
      # Reuses the proc generated in another lexical scope.
      # But it's not a problem because direct usage of sym
      # doesn't perform lookup so it doesn't care about
      # lexical scope bounds.

      let msg = initMethodCallMsg(
        "org.test.CrossScope",
        "/org/test/Obj",
        "org.test.Iface",
        "Method")
      msg.serial = 2
      msg.sender = ":1.0"

      var conn = BusConnection()
      let reply = conn.call(msg)

      check reply.kind == mtMethodReturn
      var br = initBodyReader(reply.body, reply.signature)
      check br.read[:uint32]() == 100'u32

