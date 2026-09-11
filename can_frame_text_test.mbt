///|
test "parse and normalize compact CAN frame text" {
  let frame = @moondbc.parse_can_frame(" 123#0aFF00 ").unwrap()
  assert_eq(frame.id, 0x123U)
  assert_eq(frame.payload, b"\x0a\xff\x00")
  assert_eq(frame.to_text(), Ok("123#0AFF00"))
}

///|
test "format standard and extended CAN identifiers" {
  let standard : @moondbc.CanFrame = { id: 1U, payload: b"", }
  assert_eq(standard.to_text(), Ok("001#"))
  let extended = @moondbc.parse_can_frame("1fffffff#deadbeef").unwrap()
  assert_eq(extended.id, 0x1FFFFFFFU)
  assert_eq(extended.to_text(), Ok("1FFFFFFF#DEADBEEF"))
}

///|
test "decode a parsed CAN frame through the database" {
  let database = @moondbc.parse(
      (
        #|BO_ 291 Status: 2 ECU
        #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" Logger
      ),
    ).database
  let frame = @moondbc.parse_can_frame("123#F401").unwrap()
  let decoded = database.decode_can_frame(frame).unwrap()
  assert_eq(decoded.id, 291U)
  assert_eq(decoded.signals[0].name, "Speed")
  assert_eq(decoded.signals[0].physical, 250.0)
}

///|
test "reject malformed CAN identifiers" {
  assert_eq(
    @moondbc.parse_can_frame("1234"),
    Err(@moondbc.CanFrameMissingSeparator),
  )
  assert_eq(
    @moondbc.parse_can_frame("#00"),
    Err(@moondbc.CanFrameEmptyIdentifier),
  )
  assert_eq(
    @moondbc.parse_can_frame("123456789#00"),
    Err(@moondbc.CanFrameIdentifierTooLong(9)),
  )
  assert_eq(
    @moondbc.parse_can_frame("12Z#00"),
    Err(@moondbc.CanFrameInvalidIdentifier(2, 'Z')),
  )
  assert_eq(
    @moondbc.parse_can_frame("20000000#00"),
    Err(@moondbc.CanFrameIdentifierOutOfRange(0x20000000U)),
  )
}

///|
test "reject malformed and oversized CAN payloads" {
  assert_eq(
    @moondbc.parse_can_frame("123#0"),
    Err(@moondbc.CanFrameOddPayloadLength(1)),
  )
  assert_eq(
    @moondbc.parse_can_frame("123#0Z"),
    Err(@moondbc.CanFrameInvalidPayload(1, 'Z')),
  )
  let oversized = Bytes::make(65, b'\x00')
  let frame : @moondbc.CanFrame = { id: 0x123U, payload: oversized, }
  assert_eq(frame.to_text(), Err(@moondbc.CanFramePayloadTooLong(65)))
}

///|
test "reject out-of-range identifiers during formatting" {
  let frame : @moondbc.CanFrame = { id: 0x20000000U, payload: b"", }
  assert_eq(
    frame.to_text(),
    Err(@moondbc.CanFrameIdentifierOutOfRange(0x20000000U)),
  )
}
