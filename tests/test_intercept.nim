import pkg/tinydbus
import pkg/unittest2

suite "intercept API":
  test "fakeRead":
    proc fakeRead(msg: Message): Message =
      result = initMethodReturnMsg(msg)
      var body = initBodyBuilder()
      body.add 42'u32
      result.setBody(body)

    addIntercept("org.test.Service",
                "/org/test/Object",
                "org.test.Interface",
                "Read",
                fakeRead)

    let msg = initMethodCallMsg(
      "org.test.Service",
      "/org/test/Object",
      "org.test.Interface",
      "Read")
    msg.serial = 1
    msg.sender = ":1.0"

    # call fakeRead without needing a real connection
    var conn = BusConnection()
    let reply = conn.call(msg)

    assert reply.kind == mtMethodReturn
    var br = initBodyReader(reply.body, reply.signature)
    check br.read[:uint32]() == 42'u32

