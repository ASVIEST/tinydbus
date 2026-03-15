## Optional D-Bus validation layer for tinydbus.
## It should strictly correspond specification
## can be disabled via `-d:tinydbus.disableValidation`.


const maxNameLength* = 255
const maxContainerDepth* = 32

type ValidationError* = object of DbusError

template validationError(msg: string): untyped =
  raise newException(ValidationError, msg)

proc validateObjectPath*(path: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling-object-path
  # spec: "The path must begin with an ASCII '/' (integer 47) character,
  #  and must consist of elements separated by slash characters."
  if path.len == 0:
    validationError "object path must not be empty"
  if path[0] != '/':
    validationError "object path must begin with '/'"
  if path == "/": return
  # spec: "A trailing '/' character is not allowed unless the path is the root path
  #  (a single '/' character)."
  if path[^1] == '/':
    validationError "object path must not have trailing '/' (unless root)"
  # spec: "Multiple '/' characters cannot occur in sequence."
  # spec: "No element may be the empty string."
  for elem in path[1..^1].split('/'):
    if elem.len == 0:
      validationError "object path has empty element"
    # spec: "Each element must only contain the ASCII characters "[A-Z][a-z][0-9]_""
    for c in elem:
      if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
        validationError "object path contains invalid character: '" & c & "'"

proc validateInterfaceName*(name: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-names-interface
  if name.len == 0:
    validationError "interface name must not be empty"
  # spec: "Interface names must not exceed the maximum name length."
  if name.len > maxNameLength:
    validationError "interface name exceeds " & $maxNameLength & " characters"
  # spec: "Interface names are composed of 2 or more elements separated by a period
  #  ('.') character. All elements must contain at least one character."
  let elements = name.split('.')
  if elements.len < 2:
    validationError "interface name must have at least 2 elements separated by '.'"
  for elem in elements:
    if elem.len == 0:
      validationError "interface name has empty element"
    # spec: "Each element must only contain the ASCII characters "[A-Z][a-z][0-9]_"
    #  and must not begin with a digit."
    if elem[0] in {'0'..'9'}:
      validationError "interface name element must not begin with a digit"
    for c in elem:
      if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
        validationError "interface name contains invalid character: '" & c & "'"

proc validateBusName*(name: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-names-bus
  if name.len == 0:
    validationError "bus name must not be empty"
  # spec: "Bus names must not exceed the maximum name length."
  if name.len > maxNameLength:
    validationError "bus name exceeds " & $maxNameLength & " characters"
  # spec: "Bus names must not begin with a '.' (period) character."
  if name[0] == '.':
    validationError "bus name must not begin with '.'"

  # spec: "Bus names that start with a colon (':') character are unique connection names.
  #  Other bus names are called well-known bus names."
  let isUnique = name[0] == ':'

  # spec: "Bus names are composed of 1 or more elements separated by a period ('.')
  #  character. All elements must contain at least one character."
  # spec: "Bus names must contain at least one '.' (period) character
  #  (and thus at least two elements)."
  let body = if isUnique: name[1..^1] else: name
  let elements = body.split('.')
  if elements.len < 2:
    validationError "bus name must contain at least one '.' (at least 2 elements)"
  for elem in elements:
    if elem.len == 0:
      validationError "bus name has empty element"
    # spec: "Only elements that are part of a unique connection name may begin with a
    #  digit, elements in other bus names must not begin with a digit."
    if not isUnique and elem[0] in {'0'..'9'}:
      validationError "well-known bus name element must not begin with a digit"
    # spec: "Each element must only contain the ASCII characters "[A-Z][a-z][0-9]_-",
    #  with "-" discouraged in new bus names."
    for c in elem:
      if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_', '-'}:
        validationError "bus name contains invalid character: '" & c & "'"

proc validateMemberName*(name: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-names-member
  # spec: "Must be at least 1 byte in length."
  if name.len == 0:
    validationError "member name must not be empty"
  # spec: "Must not exceed the maximum name length."
  if name.len > maxNameLength:
    validationError "member name exceeds " & $maxNameLength & " characters"
  # spec: "Must only contain the ASCII characters "[A-Z][a-z][0-9]_"
  #  and may not begin with a digit."
  if name[0] in {'0'..'9'}:
    validationError "member name must not begin with a digit"
  for c in name:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
      validationError "member name contains invalid character: '" & c & "'"

proc validateErrorName*(name: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-names-error
  # spec: "Error names have the same restrictions as interface names."
  validateInterfaceName(name)

proc skipMatchedPair(sig: string; start: int; open, close: char): int =
  ## Skip from `open` at `start` to its matching `close`. Returns position after `close`.
  var depth = 1
  var i = start + 1
  while i < sig.len and depth > 0:
    if sig[i] == open: inc depth
    elif sig[i] == close: dec depth
    inc i
  i

proc countCompleteTypes(sig: string): int =
  ## Count top-level complete types in a signature.
  var i = 0
  while i < sig.len:
    case sig[i]
    of 'y', 'b', 'n', 'q', 'i', 'u', 'x', 't', 'd', 's', 'o', 'g', 'v', 'h':
      inc result
    of 'a':
      inc i
      continue
    of '(':
      i = skipMatchedPair(sig, i, '(', ')')
      inc result
      continue
    of '{':
      i = skipMatchedPair(sig, i, '{', '}')
      inc result
      continue
    else: discard
    inc i

proc validateSignature*(sig: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-signatures
  # spec: "The maximum length of a signature is 255."
  if sig.len > maxNameLength:
    validationError "signature exceeds " & $maxNameLength & " bytes"

  var arrayDepth, structDepth, dictDepth = 0

  for i, c in sig:
    case c
    # spec: "Only type codes, open and close parentheses, and open and close curly
    #  brackets are allowed in the signature."
    of 'y', 'b', 'n', 'q', 'i', 'u', 'x', 't', 'd', 's', 'o', 'g', 'v', 'h':
      arrayDepth = 0
    of 'a':
      # spec: "The maximum depth of container type nesting is 32 array type codes
      #  and 32 open parentheses."
      inc arrayDepth
      if arrayDepth > maxContainerDepth:
        validationError "signature exceeds max array nesting depth of " & $maxContainerDepth
      # spec: "The signature is a list of single complete types. Arrays must have
      #  element types"
      if i + 1 >= sig.len:
        validationError "signature has 'a' (array) without element type"
    of '(':
      # spec: "The maximum depth of container type nesting is 32 array type codes
      #  and 32 open parentheses."
      inc structDepth
      if structDepth > maxContainerDepth:
        validationError "signature exceeds max struct nesting depth of " & $maxContainerDepth
      # spec: "structs must have both open and close parentheses"
      if i + 1 < sig.len and sig[i + 1] == ')':
        validationError "signature has empty struct '()'"
      arrayDepth = 0
    of ')':
      if structDepth == 0:
        validationError "signature has unmatched ')'"
      dec structDepth
      arrayDepth = 0
    of '{':
      # spec: "Implementations must not accept dict entries outside of arrays"
      if i == 0 or sig[i - 1] != 'a':
        validationError "signature has dict entry '{' not inside array"
      inc dictDepth
      if i + 1 >= sig.len:
        validationError "signature has incomplete dict entry"
      # spec: "the first single complete type (the "key") must be a basic type
      #  rather than a container type"
      let keyType = sig[i + 1]
      if keyType notin {'y', 'b', 'n', 'q', 'i', 'u', 'x', 't', 'd', 's', 'o', 'g', 'h'}:
        validationError "dict entry key must be a basic type, got '" & keyType & "'"
      # spec: "Implementations must not accept dict entries outside of arrays,
      #  ... dict entries with zero, one, or more than two fields"
      let closingBrace = skipMatchedPair(sig, i, '{', '}') - 1
      let fieldCount = countCompleteTypes(sig[i + 1 ..< closingBrace])
      if fieldCount != 2:
        validationError "dict entry must have exactly 2 fields, got " & $fieldCount
      arrayDepth = 0
    of '}':
      if dictDepth == 0:
        validationError "signature has unmatched '}'"
      dec dictDepth
      arrayDepth = 0
    else:
      # spec: "The STRUCT type code is not allowed in signatures, because parentheses
      #  are used instead. Similarly, the DICT_ENTRY type code is not allowed in
      #  signatures, because curly brackets are used instead."
      validationError "signature contains invalid type code: '" & c & "'"

  if structDepth != 0:
    validationError "signature has unclosed '('"
  if dictDepth != 0:
    validationError "signature has unclosed '{'"

proc validateVariantSignature*(sig: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
  # spec: "Unlike a message signature, the variant signature can contain only a
  #  single complete type."
  if sig.len == 0:
    validationError "variant signature must not be empty"
  validateSignature(sig)
  if countCompleteTypes(sig) != 1:
    validationError "variant signature must contain exactly one complete type, got '" & sig & "'"

proc validatePadding*(data: openArray[byte]; start, count: int) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
  # spec: "The alignment padding ... must always be made up of nul bytes."
  for i in 0 ..< count:
    if data[start + i] != 0:
      validationError "alignment padding byte at offset " & $(start + i) &
        " is " & $data[start + i] & ", expected 0"

proc validateBoolean*(value: uint32) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
  # spec: "BOOLEAN values are encoded in 32 bits (of which only the least significant
  #  bit is used). ...only 0 and 1 are valid values."
  if value > 1:
    validationError "boolean value must be 0 or 1, got " & $value

const maxArrayLength* = 67_108_864 ## 64 MiB, per D-Bus spec
const maxMessageLength* = 134_217_728 ## 128 MiB, per D-Bus spec

proc validateArrayLength*(length: uint32) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
  # spec: "Arrays have a maximum length defined to be 2 to the 26th power
  #  or 67108864 (64 MiB)."
  if length > maxArrayLength:
    validationError "array length " & $length &
      " exceeds maximum of " & $maxArrayLength & " bytes"

proc validateMessageLength*(length: int) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-messages
  # spec: "The maximum length of a message, including header, header alignment padding,
  #  and body is 2 to the 27th power or 134217728 (128 MiB)."
  if length > maxMessageLength:
    validationError "message length " & $length &
      " exceeds maximum of " & $maxMessageLength & " bytes"

const localPath = "/org/freedesktop/DBus/Local"
const localInterface = "org.freedesktop.DBus.Local"

proc validateLocalPath*(path: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-types
  # spec: "The special path /org/freedesktop/DBus/Local is reserved; implementations
  #  should not send messages with this path, and the reference implementation
  #  of the bus daemon will disconnect any application that attempts to do so."
  if path == localPath:
    validationError "path " & localPath & " is reserved and must not be used"

proc validateLocalInterface*(iface: string) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-types
  # spec: "The special interface org.freedesktop.DBus.Local is reserved; implementations
  #  should not send messages with this interface, and the reference implementation
  #  of the bus daemon will disconnect any application that attempts to do so."
  if iface == localInterface:
    validationError "interface " & localInterface & " is reserved and must not be used"

proc validateRequiredHeaders*(msg: Message) =
  ## https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-header-fields
  case msg.kind
  of mtMethodCall:
    # spec-table: "PATH" "MEMBER" "METHOD_CALL" "SIGNAL"
    if msg.path.len == 0:
      validationError "METHOD_CALL requires PATH header field"
    if msg.member.len == 0:
      validationError "METHOD_CALL requires MEMBER header field"
  of mtSignal:
    # spec-table: "PATH" "INTERFACE" "MEMBER" required in "SIGNAL"
    if msg.path.len == 0:
      validationError "SIGNAL requires PATH header field"
    if msg.iface.len == 0:
      validationError "SIGNAL requires INTERFACE header field"
    if msg.member.len == 0:
      validationError "SIGNAL requires MEMBER header field"
  of mtError:
    # spec-table: "ERROR_NAME" "REPLY_SERIAL" "ERROR" "METHOD_RETURN"
    if msg.errorName.len == 0:
      validationError "ERROR requires ERROR_NAME header field"
    if msg.replySerial == 0:
      validationError "ERROR requires REPLY_SERIAL header field"
  of mtMethodReturn:
    # spec-table: "REPLY_SERIAL" "ERROR" "METHOD_RETURN"
    if msg.replySerial == 0:
      validationError "METHOD_RETURN requires REPLY_SERIAL header field"
  of mtInvalid:
    validationError "message has invalid type"

proc validateCommonFields(msg: Message) =
  validateRequiredHeaders(msg)
  if msg.path.len > 0:
    validateObjectPath(msg.path)
    validateLocalPath(msg.path)
  if msg.iface.len > 0:
    validateInterfaceName(msg.iface)
    validateLocalInterface(msg.iface)
  if msg.member.len > 0: validateMemberName(msg.member)
  if msg.destination.len > 0: validateBusName(msg.destination)
  if msg.signature.len > 0: validateSignature(msg.signature)

proc validateMethodCallMsg*(msg: Message) = validateCommonFields(msg)
proc validateSignalMsg*(msg: Message) = validateCommonFields(msg)

proc validateErrorMsg*(msg: Message) =
  validateRequiredHeaders(msg)
  if msg.errorName.len > 0: validateErrorName(msg.errorName)
  if msg.destination.len > 0: validateBusName(msg.destination)
  if msg.signature.len > 0: validateSignature(msg.signature)
