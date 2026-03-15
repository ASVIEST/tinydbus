## Tests for validation_layer.nim — checks that validators accept valid inputs
## and reject invalid ones with ValidationError.

import std/strutils
import pkg/unittest2
import tinydbus

template shouldPass(body: untyped) = body
template shouldFail(body: untyped) =
  var raised = false
  try:
    body
  except CatchableError:
    raised = true
  check raised

suite "validateObjectPath":
  test "valid paths":
    shouldPass validateObjectPath("/")
    shouldPass validateObjectPath("/foo")
    shouldPass validateObjectPath("/foo/bar")
    shouldPass validateObjectPath("/a/b/c/d")
    shouldPass validateObjectPath("/org/freedesktop/DBus")
    shouldPass validateObjectPath("/with_underscores/and_123")

  test "empty":
    shouldFail validateObjectPath("")

  test "no leading slash":
    shouldFail validateObjectPath("foo")

  test "trailing slash":
    shouldFail validateObjectPath("/foo/")

  test "double slash":
    shouldFail validateObjectPath("/foo//bar")

  test "invalid characters":
    shouldFail validateObjectPath("/foo-bar")
    shouldFail validateObjectPath("/foo.bar")
    shouldFail validateObjectPath("/foo bar")

suite "validateInterfaceName":
  test "valid names":
    shouldPass validateInterfaceName("org.freedesktop.DBus")
    shouldPass validateInterfaceName("a.b")
    shouldPass validateInterfaceName("com.example.MyApp_1")

  test "empty":
    shouldFail validateInterfaceName("")

  test "single element":
    shouldFail validateInterfaceName("NoDot")

  test "exceeds max length":
    shouldFail validateInterfaceName("a." & 'b'.repeat(255))

  test "element starts with digit":
    shouldFail validateInterfaceName("org.1bad")

  test "invalid characters":
    shouldFail validateInterfaceName("org.free-desktop")
    shouldFail validateInterfaceName("org.free desktop")

  test "empty element":
    shouldFail validateInterfaceName("org..freedesktop")
    shouldFail validateInterfaceName(".org.freedesktop")

suite "validateBusName":
  test "valid well-known names":
    shouldPass validateBusName("org.freedesktop.DBus")
    shouldPass validateBusName("com.example.App")

  test "valid unique names":
    shouldPass validateBusName(":1.42")
    shouldPass validateBusName(":1.2.3")

  test "empty":
    shouldFail validateBusName("")

  test "starts with dot":
    shouldFail validateBusName(".org.bad")

  test "no dot":
    shouldFail validateBusName("nodot")

  test "well-known element starts with digit":
    shouldFail validateBusName("org.1bad")

  test "unique element starts with digit (allowed)":
    shouldPass validateBusName(":1.2")

  test "invalid characters":
    shouldFail validateBusName("org.free desktop")

  test "hyphen allowed":
    shouldPass validateBusName("org.free-desktop.DBus")

suite "validateMemberName":
  test "valid names":
    shouldPass validateMemberName("Hello")
    shouldPass validateMemberName("Get_All")
    shouldPass validateMemberName("m")

  test "empty":
    shouldFail validateMemberName("")

  test "starts with digit":
    shouldFail validateMemberName("1bad")

  test "invalid characters":
    shouldFail validateMemberName("has-hyphen")
    shouldFail validateMemberName("has.dot")

  test "exceeds max length":
    shouldFail validateMemberName('A'.repeat(256))

suite "validateErrorName":
  test "valid (same rules as interface)":
    shouldPass validateErrorName("org.freedesktop.DBus.Error")

  test "invalid":
    shouldFail validateErrorName("NoDot")

suite "validateSignature":
  test "valid basic types":
    shouldPass validateSignature("")
    shouldPass validateSignature("s")
    shouldPass validateSignature("ibus")
    shouldPass validateSignature("v")

  test "valid arrays":
    shouldPass validateSignature("ai")
    shouldPass validateSignature("aas")
    shouldPass validateSignature("a(si)")

  test "valid structs":
    shouldPass validateSignature("(si)")
    shouldPass validateSignature("(s(ii))")

  test "valid dict entries":
    shouldPass validateSignature("a{sv}")
    shouldPass validateSignature("a{sa{sv}}")

  test "exceeds max length":
    shouldFail validateSignature('s'.repeat(256))

  test "array without element type":
    shouldFail validateSignature("a")

  test "empty struct":
    shouldFail validateSignature("()")

  test "unmatched parens":
    shouldFail validateSignature("(s")
    shouldFail validateSignature("s)")

  test "dict outside array":
    shouldFail validateSignature("{sv}")

  test "dict with non-basic key":
    shouldFail validateSignature("a{(si)s}")

  test "dict with wrong field count":
    shouldFail validateSignature("a{s}")
    shouldFail validateSignature("a{sis}")

  test "invalid type code":
    shouldFail validateSignature("z")

  test "max array nesting":
    shouldPass validateSignature("a".repeat(32) & "i")
    shouldFail validateSignature("a".repeat(33) & "i")

  test "max struct nesting":
    shouldPass validateSignature("(".repeat(32) & "i" & ")".repeat(32))
    shouldFail validateSignature("(".repeat(33) & "i" & ")".repeat(33))

suite "validateVariantSignature":
  test "valid single type":
    shouldPass validateVariantSignature("s")
    shouldPass validateVariantSignature("ai")
    shouldPass validateVariantSignature("(si)")
    shouldPass validateVariantSignature("a{sv}")

  test "empty":
    shouldFail validateVariantSignature("")

  test "multiple types":
    shouldFail validateVariantSignature("si")

suite "validatePadding":
  test "valid all-zero padding":
    shouldPass validatePadding([0'u8, 0, 0], 0, 3)

  test "non-zero padding":
    shouldFail validatePadding([0'u8, 1, 0], 0, 3)

suite "validateBoolean":
  test "valid":
    shouldPass validateBoolean(0'u32)
    shouldPass validateBoolean(1'u32)

  test "invalid":
    shouldFail validateBoolean(2'u32)
    shouldFail validateBoolean(255'u32)

suite "validateArrayLength":
  test "valid":
    shouldPass validateArrayLength(0'u32)
    shouldPass validateArrayLength(maxArrayLength.uint32)

  test "exceeds max":
    shouldFail validateArrayLength(maxArrayLength.uint32 + 1)

suite "validateMessageLength":
  test "valid":
    shouldPass validateMessageLength(0)
    shouldPass validateMessageLength(maxMessageLength)

  test "exceeds max":
    shouldFail validateMessageLength(maxMessageLength + 1)

suite "validateLocalPath":
  test "normal path allowed":
    shouldPass validateLocalPath("/org/freedesktop/DBus")

  test "reserved path rejected":
    shouldFail validateLocalPath("/org/freedesktop/DBus/Local")

suite "validateLocalInterface":
  test "normal interface allowed":
    shouldPass validateLocalInterface("org.freedesktop.DBus")

  test "reserved interface rejected":
    shouldFail validateLocalInterface("org.freedesktop.DBus.Local")

suite "validateRequiredHeaders":
  test "valid METHOD_CALL":
    shouldPass validateRequiredHeaders(Message(
      kind: mtMethodCall, path: "/foo", member: "Bar"))

  test "METHOD_CALL missing path":
    shouldFail validateRequiredHeaders(Message(
      kind: mtMethodCall, member: "Bar"))

  test "METHOD_CALL missing member":
    shouldFail validateRequiredHeaders(Message(
      kind: mtMethodCall, path: "/foo"))

  test "valid SIGNAL":
    shouldPass validateRequiredHeaders(Message(
      kind: mtSignal, path: "/foo", iface: "a.b", member: "Sig"))

  test "SIGNAL missing interface":
    shouldFail validateRequiredHeaders(Message(
      kind: mtSignal, path: "/foo", member: "Sig"))

  test "valid ERROR":
    shouldPass validateRequiredHeaders(Message(
      kind: mtError, errorName: "a.b", replySerial: 1))

  test "ERROR missing error name":
    shouldFail validateRequiredHeaders(Message(
      kind: mtError, replySerial: 1))

  test "valid METHOD_RETURN":
    shouldPass validateRequiredHeaders(Message(
      kind: mtMethodReturn, replySerial: 1))

  test "METHOD_RETURN missing reply serial":
    shouldFail validateRequiredHeaders(Message(
      kind: mtMethodReturn))

  test "mtInvalid always fails":
    shouldFail validateRequiredHeaders(Message(kind: mtInvalid))

suite "validateMethodCallMsg (full)":
  test "valid":
    shouldPass validateMethodCallMsg(Message(
      kind: mtMethodCall, path: "/foo", member: "Bar",
      destination: "org.example.Bus", iface: "org.example.Iface",
      signature: "s"))

  test "invalid path in message":
    shouldFail validateMethodCallMsg(Message(
      kind: mtMethodCall, path: "bad", member: "Bar"))

  test "reserved local path":
    shouldFail validateMethodCallMsg(Message(
      kind: mtMethodCall, path: "/org/freedesktop/DBus/Local", member: "Bar"))

  test "reserved local interface":
    shouldFail validateMethodCallMsg(Message(
      kind: mtMethodCall, path: "/foo", member: "Bar",
      iface: "org.freedesktop.DBus.Local"))
