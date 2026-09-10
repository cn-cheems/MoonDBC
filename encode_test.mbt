///|
test "encode aligned Intel raw and physical values" {
  let result = @moondbc.parse(
    (
      #|BO_ 30 Powertrain: 4 ECU
      #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
    ),
  )
  let signal = result.database.messages[0].signals[0]
  let base = b"\xff\xff\xaa\x55"
  assert_eq(
    signal.encode_raw(base, @moondbc.UnsignedRaw(8000UL)),
    Ok(b"\x40\x1f\xaa\x55"),
  )
  assert_eq(signal.encode(base, 1000.0), Ok(b"\x40\x1f\xaa\x55"))
  assert_eq(base, b"\xff\xff\xaa\x55")
}

///|
test "encode unaligned Intel signal without changing adjacent bits" {
  let result = @moondbc.parse(
    (
      #|BO_ 31 Packed: 2 ECU
      #| SG_ Counter : 3|10@1+ (1,0) [0|1023] "" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  let encoded = signal
    .encode_raw(b"\x07\xe0", @moondbc.UnsignedRaw(725UL))
    .unwrap()
  assert_eq(encoded, b"\xaf\xf6")
  assert_eq(signal.decode_raw(encoded), Ok(@moondbc.UnsignedRaw(725UL)))
}

///|
test "encode unaligned signed Motorola signal" {
  let result = @moondbc.parse(
    (
      #|BO_ 32 PackedBigEndian: 2 ECU
      #| SG_ Temperature : 3|12@0- (1,0) [-2048|2047] "degC" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  let encoded = signal
    .encode_raw(b"\xf0\x00", @moondbc.SignedRaw(-20L))
    .unwrap()
  assert_eq(encoded, b"\xff\xec")
  assert_eq(signal.decode_raw(encoded), Ok(@moondbc.SignedRaw(-20L)))
}

///|
test "reject mismatched and overflowing raw values" {
  let result = @moondbc.parse(
    (
      #|BO_ 33 State: 1 ECU
      #| SG_ Level : 0|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(
    signal.encode_raw(b"\x00", @moondbc.SignedRaw(1L)),
    Err(@moondbc.ValueKindMismatch(@moondbc.Unsigned, @moondbc.SignedRaw(1L))),
  )
  assert_eq(
    signal.encode_raw(b"\x00", @moondbc.UnsignedRaw(256UL)),
    Err(@moondbc.RawValueOutOfRange(@moondbc.UnsignedRaw(256UL), 8)),
  )
}

///|
test "validate physical value and frame bounds" {
  let result = @moondbc.parse(
    (
      #|BO_ 34 State: 1 ECU
      #| SG_ Level : 0|8@1+ (0.5,0) [0|100] "percent" Logger
    ),
  )
  let signal = result.database.messages[0].signals[0]
  assert_eq(
    signal.encode(b"\x00", 101.0),
    Err(@moondbc.PhysicalValueOutOfRange(101.0, 0.0, 100.0)),
  )
  assert_eq(
    signal.encode_raw(b"", @moondbc.UnsignedRaw(10UL)),
    Err(@moondbc.EncodeFrameTooShort(8, 0)),
  )
}

///|
test "validate signal layout before physical conversion" {
  let signal : @moondbc.Signal = {
    name: "Invalid",
    start_bit: 0,
    bit_length: 65,
    byte_order: @moondbc.Intel,
    value_kind: @moondbc.Unsigned,
    factor: 1.0,
    offset: 0.0,
    minimum: 0.0,
    maximum: 1.0,
    unit: "",
    receivers: [],
    multiplex: @moondbc.Plain,
  }
  assert_eq(
    signal.encode(b"\x00", 0.0),
    Err(@moondbc.EncodeInvalidLayout(0, 65)),
  )
}
