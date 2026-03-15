## nim dbus protocol implementation.

import std/[os, strutils, nativesockets, macrocache, macros, sequtils]

when defined(posix):
  import std/posix

  type SockaddrUn {.importc: "struct sockaddr_un",
                    header: "<sys/un.h>".} = object
    sun_family {.importc.}: cushort
    sun_path {.importc.}: array[108, char]

  const MsgNosignal {.importc: "MSG_NOSIGNAL", header: "<sys/socket.h>".}: cint = 0x4000

type
  ObjectPath* = distinct string
  DbusSignature* = distinct string

  MessageType* = enum
    mtInvalid = 0
    mtMethodCall = 1
    mtMethodReturn = 2
    mtError = 3
    mtSignal = 4

  HeaderField = enum
    hfInvalid = 0
    hfPath = 1
    hfInterface = 2
    hfMember = 3
    hfErrorName = 4
    hfReplySerial = 5
    hfDestination = 6
    hfSender = 7
    hfSignature = 8
    hfUnixFds = 9

  Message* = ref object
    kind*: MessageType
    flags*: uint8
    serial*: uint32
    path*, iface*, member*, errorName*, destination*, sender*, signature*: string
    replySerial*: uint32
    body*: seq[byte]

  BusConnection* = ref object
    fd: SocketHandle
    nextSerial: uint32

  DbusError* = object of CatchableError

proc `$`*(s: ObjectPath): string {.borrow.}
proc `$`*(s: DbusSignature): string {.borrow.}
proc `==`*(a, b: ObjectPath): bool {.borrow.}
proc `==`*(a, b: DbusSignature): bool {.borrow.}
proc len*(s: ObjectPath): int {.borrow.}
proc len*(s: DbusSignature): int {.borrow.}

proc alignmentOf*(c: char): int {.inline.} =
  case c
  of 'y': 1
  of 'n', 'q': 2
  of 'b', 'i', 'u', 's', 'o', 'a': 4
  of 'x', 't', 'd', '(', '{': 8
  else: 1

type Writer = object
  buf: seq[byte]

proc len(w: Writer): int = w.buf.len

proc alignTo(w: var Writer; n: int) {.inline.} =
  w.buf.setLen(w.buf.len + (n - (w.buf.len mod n)) mod n)

proc put(w: var Writer; v: uint8) {.inline.} = w.buf.add v

template putInt(w: var Writer; v: untyped; size: static int) =
  w.alignTo(size)
  for i in 0 ..< size:
    let shift = when cpuEndian == bigEndian: (size - 1 - i) * 8 else: i * 8
    w.buf.add byte((v shr shift) and 0xFF)

proc put(w: var Writer; v: uint16) {.inline.} = w.putInt(v, 2)
proc put(w: var Writer; v: uint32) {.inline.} = w.putInt(v, 4)
proc put(w: var Writer; v: uint64) {.inline.} = w.putInt(v, 8)

proc putAt(w: var Writer; pos: int; v: uint32) =
  for i in 0 ..< 4:
    let shift = when cpuEndian == bigEndian: (3 - i) * 8 else: i * 8
    w.buf[pos + i] = byte((v shr shift) and 0xFF)

proc put(w: var Writer; v: int16) {.inline.} = w.put(cast[uint16](v))
proc put(w: var Writer; v: int32) {.inline.} = w.put(cast[uint32](v))
proc put(w: var Writer; v: int64) {.inline.} = w.put(cast[uint64](v))
proc put(w: var Writer; v: bool) {.inline.} = w.put(if v: 1u32 else: 0u32)
proc put(w: var Writer; v: float64) {.inline.} = w.put(cast[uint64](v))

proc putStr(w: var Writer; s: string; lenSize: static int) =
  when lenSize == 4: w.put(uint32(s.len))
  else: w.put(uint8(s.len))
  for c in s: w.buf.add byte(c)
  w.buf.add 0

proc put(w: var Writer; v: string) {.inline.} = w.putStr(v, 4)
proc put(w: var Writer; v: ObjectPath) {.inline.} = w.putStr(string(v), 4)
proc put(w: var Writer; v: DbusSignature) {.inline.} = w.putStr(string(v), 1)

type Reader = object
  data: seq[byte]
  pos: int
  baseOffset: int
  bigEndian: bool

proc alignTo(r: var Reader; n: int) {.inline.} =
  r.pos += (n - ((r.baseOffset + r.pos) mod n)) mod n

proc checkRead(r: Reader; n: int) {.inline.} =
  if r.pos + n > r.data.len:
    raise newException(DbusError, "read past end")

proc get(r: var Reader; T: type uint8): uint8 {.inline.} =
  r.checkRead(1)
  result = r.data[r.pos]
  r.pos += 1

template getInt(r: var Reader; T: type; size: static int): untyped =
  r.alignTo(size)
  r.checkRead(size)
  var v: T
  for i in 0 ..< size:
    let shift = if r.bigEndian: (size - 1 - i) * 8 else: i * 8
    v = v or (T(r.data[r.pos + i]) shl shift)
  r.pos += size
  v

proc get(r: var Reader; T: type uint16): uint16 {.inline.} = r.getInt(uint16, 2)
proc get(r: var Reader; T: type uint32): uint32 {.inline.} = r.getInt(uint32, 4)
proc get(r: var Reader; T: type uint64): uint64 {.inline.} = r.getInt(uint64, 8)

proc get(r: var Reader; T: type int16): int16 {.inline.} = cast[int16](r.get(uint16))
proc get(r: var Reader; T: type int32): int32 {.inline.} = cast[int32](r.get(uint32))
proc get(r: var Reader; T: type int64): int64 {.inline.} = cast[int64](r.get(uint64))
proc get(r: var Reader; T: type bool): bool {.inline.} = r.get(uint32) != 0
proc get(r: var Reader; T: type float64): float64 {.inline.} = cast[float64](r.get(uint64))

proc getStr(r: var Reader; lenSize: static int): string =
  let length = when lenSize == 4: int(r.get(uint32)) else: int(r.get(uint8))
  r.checkRead(length + 1)
  result = newString(length)
  for i in 0 ..< length: result[i] = char(r.data[r.pos + i])
  r.pos += length + 1

proc get(r: var Reader; T: type string): string {.inline.} = r.getStr(4)
proc get(r: var Reader; T: type ObjectPath): ObjectPath {.inline.} = ObjectPath(r.getStr(4))
proc get(r: var Reader; T: type DbusSignature): DbusSignature {.inline.} = DbusSignature(r.getStr(1))

proc sigChar(T: type uint8): char = 'y'
proc sigChar(T: type bool): char = 'b'
proc sigChar(T: type int16): char = 'n'
proc sigChar(T: type uint16): char = 'q'
proc sigChar(T: type int32): char = 'i'
proc sigChar(T: type uint32): char = 'u'
proc sigChar(T: type int64): char = 'x'
proc sigChar(T: type uint64): char = 't'
proc sigChar(T: type float64): char = 'd'
proc sigChar(T: type string): char = 's'
proc sigChar(T: type ObjectPath): char = 'o'
proc sigChar(T: type DbusSignature): char = 'g'

type
  BodyBuilder* = object
    w: Writer
    sig*: string
    arrayDepth: int

  ArrayBuilder* = object
    parent: ptr BodyBuilder
    lenPos, dataStart: int

proc initBodyBuilder*(): BodyBuilder = BodyBuilder()

proc add*[T](b: var BodyBuilder; v: T) =
  if b.arrayDepth == 0: b.sig.add sigChar(T)
  b.w.put(v)

proc addArrayBegin*(b: var BodyBuilder; elementSig: string): ArrayBuilder =
  if b.arrayDepth == 0:
    b.sig.add 'a'
    b.sig.add elementSig
  b.arrayDepth += 1
  b.w.put(0u32)
  let lenPos = b.w.buf.len - 4
  if elementSig.len > 0: b.w.alignTo(alignmentOf(elementSig[0]))
  ArrayBuilder(parent: addr b, lenPos: lenPos, dataStart: b.w.buf.len)

proc finish*(ab: ArrayBuilder) =
  ab.parent.arrayDepth -= 1
  ab.parent.w.putAt(ab.lenPos, uint32(ab.parent.w.buf.len - ab.dataStart))

proc addVariant*(b: var BodyBuilder; valueSig: string;
                 value: proc(b: var BodyBuilder)) =
  if b.arrayDepth == 0: b.sig.add 'v'
  b.w.put(DbusSignature(valueSig))
  let savedSig = b.sig
  b.sig = ""
  value(b)
  b.sig = savedSig

proc addStructBegin*(b: var BodyBuilder) =
  if b.arrayDepth == 0: b.sig.add '('
  b.w.alignTo(8)
proc addStructEnd*(b: var BodyBuilder) {.inline.} =
  if b.arrayDepth == 0: b.sig.add ')'

proc finish*(b: BodyBuilder): (string, seq[byte]) = (b.sig, b.w.buf)

type BodyReader* = object
  r: Reader
  sig*: string
  sigPos*: int

proc initBodyReader*(body: seq[byte]; signature: string): BodyReader =
  BodyReader(r: Reader(data: body), sig: signature)

proc read*[T](br: var BodyReader): T =
  br.sigPos += 1
  br.r.get(T)

proc readArrayBegin*(br: var BodyReader; elementSig: string): int =
  br.sigPos += 1 + elementSig.len
  let length = int(br.r.get(uint32))
  if elementSig.len > 0: br.r.alignTo(alignmentOf(elementSig[0]))
  br.r.pos + length

proc readArrayHasMore*(br: BodyReader; endPos: int): bool {.inline.} = br.r.pos < endPos

proc readVariantSignature*(br: var BodyReader): string =
  br.sigPos += 1
  string(br.r.get(DbusSignature))

proc readStructBegin*(br: var BodyReader) =
  br.sigPos += 1
  br.r.alignTo(8)

proc readStructEnd*(br: var BodyReader) {.inline.} = br.sigPos += 1
proc atEnd*(br: BodyReader): bool {.inline.} = br.r.pos >= br.r.data.len

proc initMethodCallMsg*(destination, path, iface, member: string): Message =
  Message(kind: mtMethodCall, destination: destination,
          path: path, iface: iface, member: member)

proc initSignalMsg*(path, iface, member: string): Message =
  Message(kind: mtSignal, path: path, iface: iface, member: member)

proc initMethodReturnMsg*(replyTo: Message): Message =
  Message(kind: mtMethodReturn, replySerial: replyTo.serial,
          destination: replyTo.sender)

proc initErrorMsg*(replyTo: Message; name: string): Message =
  Message(kind: mtError, replySerial: replyTo.serial,
          destination: replyTo.sender, errorName: name)

proc setBody*(msg: Message; builder: BodyBuilder) =
  let (sig, data) = builder.finish()
  msg.signature = sig
  msg.body = data




proc serialize(msg: Message; serial: uint32): seq[byte] =
  var h: Writer
  h.put(when cpuEndian == bigEndian: uint8('B') else: uint8('l'))
  h.put(uint8(ord(msg.kind)))
  h.put(msg.flags)
  h.put(1u8)
  h.put(uint32(msg.body.len))
  h.put(serial)
  h.put(0u32) # placeholder for fields length
  let fieldsStart = h.len

  template field(hf: HeaderField; sig: string; val: untyped) =
    h.alignTo(8)
    h.put(uint8(ord(hf)))
    h.put(DbusSignature(sig))
    h.put(val)

  if msg.path.len > 0:        field(hfPath, "o", msg.path)
  if msg.iface.len > 0:       field(hfInterface, "s", msg.iface)
  if msg.member.len > 0:      field(hfMember, "s", msg.member)
  if msg.errorName.len > 0:   field(hfErrorName, "s", msg.errorName)
  if msg.replySerial != 0:    field(hfReplySerial, "u", msg.replySerial)
  if msg.destination.len > 0: field(hfDestination, "s", msg.destination)
  if msg.sender.len > 0:      field(hfSender, "s", msg.sender)
  if msg.signature.len > 0:   field(hfSignature, "g", DbusSignature(msg.signature))

  h.putAt(12, uint32(h.len - fieldsStart))
  h.alignTo(8)
  result = h.buf
  result.add msg.body

proc deserialize(data: seq[byte]): Message =
  if data.len < 16:
    raise newException(DbusError, "message too short")

  var r = Reader(data: data)
  let endianness = r.get(uint8)
  case char(endianness)
  of 'l': r.bigEndian = false
  of 'B': r.bigEndian = true
  else: raise newException(DbusError, "invalid endian marker: " & $char(endianness))

  let msgType = r.get(uint8)
  let flags = r.get(uint8)
  let version = r.get(uint8)
  if version != 1:
    raise newException(DbusError, "unsupported protocol version: " & $version)

  let bodyLen = r.get(uint32)
  let serial = r.get(uint32)
  let fieldsLen = r.get(uint32)
  result = Message(kind: MessageType(msgType), flags: flags, serial: serial)

  let fieldsEnd = r.pos + int(fieldsLen)
  while r.pos < fieldsEnd:
    r.alignTo(8)
    if r.pos >= fieldsEnd: break
    let fc = HeaderField(r.get(uint8))
    discard r.get(DbusSignature) # field type signature
    case fc
    of hfPath:        result.path = r.get(string)
    of hfInterface:   result.iface = r.get(string)
    of hfMember:      result.member = r.get(string)
    of hfErrorName:   result.errorName = r.get(string)
    of hfReplySerial: result.replySerial = r.get(uint32)
    of hfDestination: result.destination = r.get(string)
    of hfSender:      result.sender = r.get(string)
    of hfSignature:   result.signature = string(r.get(DbusSignature))
    of hfUnixFds:     discard r.get(uint32)
    of hfInvalid:     raise newException(DbusError, "invalid header field")

  r.pos = fieldsEnd
  r.alignTo(8)
  if bodyLen > 0:
    if r.pos + int(bodyLen) > data.len:
      raise newException(DbusError, "body extends past message data")
    result.body = data[r.pos ..< r.pos + int(bodyLen)]



# Socket magic:

proc recvAll(fd: SocketHandle; buf: pointer; count: int) =
  var offset = 0
  while offset < count:
    let n = recv(fd, cast[pointer](cast[int](buf) + offset), count - offset, 0)
    if n <= 0: raise newException(DbusError, "recv failed")
    offset += int(n)

proc sendAll(fd: SocketHandle; buf: pointer; count: int) =
  var offset = 0
  while offset < count:
    let n = send(fd, cast[pointer](cast[int](buf) + offset),
                 count - offset, MsgNosignal)
    if n <= 0: raise newException(DbusError, "send failed")
    offset += int(n)

proc sendAll(fd: SocketHandle; data: seq[byte]) =
  if data.len > 0: sendAll(fd, addr data[0], data.len)

proc sendAll(fd: SocketHandle; s: string) =
  if s.len > 0: sendAll(fd, addr s[0], s.len)

proc recvLine(fd: SocketHandle): string =
  var c: char
  while true:
    if recv(fd, addr c, 1, 0) <= 0: raise newException(DbusError, "recvLine failed")
    result.add c
    if c == '\n': break




proc parseAddress(address: string): (string, bool) =
  if not address.startsWith("unix:"):
    raise newException(DbusError, "unsupported bus address: " & address)
  for part in address[5 .. ^1].split(','):
    if part.startsWith("path="):     return (part[5 .. ^1], false)
    if part.startsWith("abstract="): return (part[9 .. ^1], true)
  raise newException(DbusError, "no path in bus address: " & address)

proc connectUnixSocket(path: string; isAbstract: bool): SocketHandle =
  let fd = createNativeSocket(Domain.AF_UNIX, SockType.SOCK_STREAM,
                              Protocol.IPPROTO_IP)
  if fd == osInvalidSocket:
    raise newException(DbusError, "socket() failed")
  var sa: SockaddrUn
  sa.sun_family = cushort(posix.AF_UNIX)
  let offset = int(isAbstract)
  for i in 0 ..< min(path.len, sizeof(sa.sun_path) - 1 - offset):
    sa.sun_path[i + offset] = path[i]
  let addrLen = SockLen(2 + offset + path.len + ord(not isAbstract))
  if posix.connect(fd, cast[ptr SockAddr](addr sa), addrLen) != 0:
    fd.close()
    raise newException(DbusError, "connect() failed: " & $strerror(errno))
  fd

proc uidHex(): string =
  for c in $posix.getuid():
    result.add toHex(ord(c), 2).toLowerAscii()

proc authenticate(fd: SocketHandle) =
  sendAll(fd, "\0")
  sendAll(fd, "AUTH EXTERNAL " & uidHex() & "\r\n")
  let response = recvLine(fd)
  if not response.startsWith("OK"):
    raise newException(DbusError, "auth failed: " & response.strip())
  sendAll(fd, "BEGIN\r\n")




proc close*(conn: BusConnection) =
  if conn.fd != osInvalidSocket:
    conn.fd.close()
    conn.fd = osInvalidSocket

proc `=destroy`(conn: typeof(BusConnection()[])) =
  if conn.fd != osInvalidSocket:
    conn.fd.close()

proc connectBus*(address: string): BusConnection =
  let (path, isAbstract) = parseAddress(address)
  let fd = connectUnixSocket(path, isAbstract)
  authenticate(fd)
  BusConnection(fd: fd, nextSerial: 1)

proc connectSession*(): BusConnection =
  let address = getEnv("DBUS_SESSION_BUS_ADDRESS")
  if address.len == 0:
    raise newException(DbusError, "DBUS_SESSION_BUS_ADDRESS not set")
  connectBus(address)

proc connectSystem*(): BusConnection =
  connectBus("unix:path=/var/run/dbus/system_bus_socket")

proc send*(conn: BusConnection; msg: Message): uint32 =
  let serial = conn.nextSerial
  conn.nextSerial += 1
  msg.serial = serial
  sendAll(conn.fd, serialize(msg, serial))
  serial

proc readU32(data: openArray[byte]; off: int; bigEndian: bool): uint32 {.inline.} =
  for i in 0 ..< 4:
    let shift = if bigEndian: (3 - i) * 8 else: i * 8
    result = result or (uint32(data[off + i]) shl shift)

proc receive*(conn: BusConnection): Message =
  var hdr: array[16, byte]
  recvAll(conn.fd, addr hdr[0], 16)
  let be = case char(hdr[0])
    of 'l': false
    of 'B': true
    else: raise newException(DbusError, "invalid endian marker")

  let bodyLen = readU32(hdr, 4, be)
  let fieldsLen = readU32(hdr, 12, be)

  let fieldsPadded = int(fieldsLen) + ((8 - (int(fieldsLen) mod 8)) mod 8)
  let totalSize = 16 + fieldsPadded + int(bodyLen)
  var fullMsg = newSeq[byte](totalSize)
  copyMem(addr fullMsg[0], addr hdr[0], 16)
  if totalSize > 16:
    recvAll(conn.fd, addr fullMsg[16], totalSize - 16)
  deserialize(fullMsg)

proc rawCall*(conn: BusConnection; msg: Message): Message =
  let serial = conn.send(msg)
  while true:
    let reply = conn.receive()
    if reply.replySerial == serial:
      if reply.kind == mtError:
        var errDetail = reply.errorName
        if reply.body.len > 0 and reply.signature.len > 0 and
           reply.signature[0] == 's':
          var br = initBodyReader(reply.body, reply.signature)
          errDetail.add ": " & br.read[:string]()
        raise newException(DbusError, errDetail)
      return reply

# Compile-time intercept support:

const
  interceptVersion = CacheCounter"tinydbus.interceptVer"
  generatedVersion = CacheCounter"tinydbus.generatedVer"
  interceptRegistry* = CacheSeq"tinydbus.interceptors"

when defined(tinydbus.runtimeDispatch):
  # nimcall cheaper than {.closure.} btw
  var callImpl: proc(
    conn: BusConnection; msg: Message): Message {.nimcall.} = rawCall
else:
  const resolveCallSyms = CacheSeq"tinydbus.resolveCallSyms"

macro addIntercept*(dest, path, iface, member: static string;
                    handler: typed) =
  interceptVersion.inc()
  interceptRegistry.add newTree(nnkTupleConstr,
    newLit(dest), newLit(path), newLit(iface), newLit(member), handler)

proc matchField(conds: var seq[NimNode]; msgSym, field, value: NimNode) =
  if value.strVal.len > 0:
    conds.add infix(newDotExpr(msgSym, field), "==", value)

macro call*(conn: BusConnection; msg: Message): Message =
  if interceptRegistry.len == 0:
    return newCall(
      when defined(tinydbus.runtimeDispatch): bindSym"callImpl"
      else: bindSym"rawCall", conn, msg)
  
  if interceptVersion.value == generatedVersion.value:
    newCall(
      when defined(tinydbus.runtimeDispatch): bindSym"callImpl"
      else: resolveCallSyms[^1], conn, msg)
  else:
    generatedVersion.inc(
      interceptVersion.value -
      generatedVersion.value)
    let implName = genSym(nskProc, "resolveCallImpl")
    when not defined(tinydbus.runtimeDispatch):
      resolveCallSyms.add implName
    let connParam = ident"conn"
    let msgParam = ident"msg"
    var ifStmt = newNimNode(nnkIfStmt)

    for entry in interceptRegistry:
      let (dest, path, iface, member, handler) =
        (entry[0], entry[1], entry[2], entry[3], entry[4])

      var conds: seq[NimNode] = @[]
      conds.matchField(msgParam, ident"destination", dest)
      conds.matchField(msgParam, ident"path", path)
      conds.matchField(msgParam, ident"iface", iface)
      conds.matchField(msgParam, ident"member", member)

      let cond =
        if conds.len == 0: newLit(true)
        else: conds.foldl(infix(a, "and", b))

      let action = newCall(handler, msgParam)
      ifStmt.add newTree(nnkElifBranch, cond, action)

    ifStmt.add newTree(
      nnkElse,
      newCall(bindSym"rawCall", connParam, msgParam))

    let procDef = newProc(
      name = implName,
      params = [bindSym"Message",
                newIdentDefs(connParam, bindSym"BusConnection"),
                newIdentDefs(msgParam, bindSym"Message")],
      body = ifStmt)

    when defined(tinydbus.runtimeDispatch):
      newStmtList(
        procDef,
        newAssignment(bindSym"callImpl", implName),
        newCall(bindSym"callImpl", conn, msg))
    else:
      newStmtList(procDef, newCall(implName, conn, msg))

when defined(tinydbus.runtimeDispatch):
  macro callSym*(): NimNode = bindSym"callImpl"
else:
  macro callSym*(): NimNode = resolveCallSyms[^1]

# Basic helpers:

proc hello*(conn: BusConnection): string =
  let msg = initMethodCallMsg("org.freedesktop.DBus", "/org/freedesktop/DBus",
                          "org.freedesktop.DBus", "Hello")
  var br = initBodyReader(conn.call(msg).body, "s")
  br.read[:string]()

proc openSessionBus*(): (BusConnection, string) =
  let conn = connectSession()
  (conn, conn.hello())

proc openSystemBus*(): (BusConnection, string) =
  let conn = connectSystem()
  (conn, conn.hello())

