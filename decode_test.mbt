///|
test "decode aligned unsigned Intel signal" {
  let result = @moondbc.parse(
    (
      #|BO_ 256 Powertrain: 8 ECU
      #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
    ),
  )
  let signal = result.database.messages[0].signals[0]
  let payload = b"\x40\x1f\x00\x00\x00\x00\x00\x00"
  assert_eq(signal.decode_raw(payload), Ok(@moondbc.UnsignedRaw(8000UL)))
  assert_eq(signal.decode(payload), Ok(1000.0))
}

///|
test "decode unaligned Intel signal across bytes" {
  let result = @moondbc.parse(
    (
      #|BO_ 10 Packed: 2 ECU
      #| SG_ Counter : 3|10@1+ (1,0) [0|1023] "" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(signal.decode_raw(b"\xa8\x16"), Ok(@moondbc.UnsignedRaw(725UL)))
}

///|
test "sign extend and scale signed Intel signal" {
  let result = @moondbc.parse(
    (
      #|BO_ 11 Temperatures: 1 ECU
      #| SG_ Temperature : 0|8@1- (0.5,10) [-54|73.5] "degC" Display
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(signal.decode_raw(b"\xd8"), Ok(@moondbc.SignedRaw(-40L)))
  assert_eq(signal.decode(b"\xd8"), Ok(-10.0))
}

///|
test "decode full-width signed Intel signal" {
  let result = @moondbc.parse(
    (
      #|BO_ 12 Wide: 8 ECU
      #| SG_ Signed64 : 0|64@1- (1,0) [0|0] "" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(
    signal.decode_raw(b"\xff\xff\xff\xff\xff\xff\xff\xff"),
    Ok(@moondbc.SignedRaw(-1L)),
  )
}

///|
test "reject short Intel payload" {
  let result = @moondbc.parse(
    (
      #|BO_ 13 Mixed: 8 ECU
      #| SG_ TooFar : 12|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  let message = result.database.messages[0]
  assert_eq(
    message.signals[0].decode_raw(b"\x00\x00"),
    Err(@moondbc.FrameTooShort(20, 16)),
  )
}

///|
test "decode aligned Motorola signal" {
  let result = @moondbc.parse(
    (
      #|BO_ 20 BigEndian: 2 ECU
      #| SG_ Word : 7|16@0+ (0.5,1) [0|32768.5] "V" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(signal.decode_raw(b"\x12\x34"), Ok(@moondbc.UnsignedRaw(4660UL)))
  assert_eq(signal.decode(b"\x12\x34"), Ok(2331.0))
}

///|
test "decode unaligned signed Motorola signal" {
  let result = @moondbc.parse(
    (
      #|BO_ 21 PackedBigEndian: 2 ECU
      #| SG_ Temperature : 3|12@0- (1,0) [-2048|2047] "degC" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(signal.decode_raw(b"\x0f\xec"), Ok(@moondbc.SignedRaw(-20L)))
  assert_eq(signal.decode(b"\x0f\xec"), Ok(-20.0))
}

///|
test "reject short Motorola payload" {
  let result = @moondbc.parse(
    (
      #|BO_ 22 BigEndian: 2 ECU
      #| SG_ Word : 7|16@0+ (1,0) [0|65535] "" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(signal.decode_raw(b"\x12"), Err(@moondbc.FrameTooShort(16, 8)))
}

///|
test "reject invalid manually constructed signal layout" {
  let signal : @moondbc.Signal = {
    name: "Invalid",
    start_bit: -1,
    bit_length: 0,
    byte_order: @moondbc.Intel,
    value_kind: @moondbc.Unsigned,
    factor: 1.0,
    offset: 0.0,
    minimum: 0.0,
    maximum: 0.0,
    unit: "",
    receivers: [],
    multiplex: @moondbc.Plain,
  }
  assert_eq(signal.decode_raw(b""), Err(@moondbc.InvalidSignalLayout(-1, 0)))
}
