///|
test "decode a complete message and attach value labels" {
  let result = @moondbc.parse(
    (
      #|BO_ 200 Powertrain: 3 ECU
      #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
      #| SG_ Gear : 16|8@1+ (1,0) [0|7] "" Dashboard
      #|VAL_ 200 Gear 0 "Neutral" 1 "Drive";
    ),
  )
  let decoded = result.database.decode_frame(200U, b"\x40\x1f\x01").unwrap()
  assert_eq(decoded.id, 200U)
  assert_eq(decoded.name, "Powertrain")
  assert_eq(decoded.signals.length(), 2)
  assert_eq(decoded.signals[0].name, "EngineSpeed")
  assert_eq(decoded.signals[0].physical, 1000.0)
  assert_eq(decoded.signals[0].unit, "rpm")
  assert_eq(decoded.signals[0].label, None)
  assert_eq(decoded.signals[1].name, "Gear")
  assert_eq(decoded.signals[1].label, Some("Drive"))
}

///|
test "dispatch multiplexed signals by selector" {
  let result = @moondbc.parse(
    (
      #|BO_ 201 Sensor: 2 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" Logger
      #| SG_ Voltage m1 : 8|8@1+ (0.5,0) [0|127.5] "V" Logger
      #| SG_ Current m2 : 8|8@1+ (0.25,0) [0|63.75] "A" Logger
    ),
  )
  let voltage = result.database.decode_frame(201U, b"\x01\x0a").unwrap()
  assert_eq(voltage.signals.length(), 2)
  assert_eq(voltage.signals[0].name, "Mode")
  assert_eq(voltage.signals[1].name, "Voltage")
  assert_eq(voltage.signals[1].physical, 5.0)
  let current = result.database.decode_frame(201U, b"\x02\x0c").unwrap()
  assert_eq(current.signals.length(), 2)
  assert_eq(current.signals[1].name, "Current")
  assert_eq(current.signals[1].physical, 3.0)
}

///|
test "report missing and duplicate multiplexers" {
  let missing = @moondbc.parse(
    (
      #|BO_ 202 Missing: 1 ECU
      #| SG_ Branch m1 : 0|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  assert_eq(
    missing.database.decode_frame(202U, b"\x00"),
    Err(@moondbc.MissingMultiplexer),
  )
  let duplicate = @moondbc.parse(
    (
      #|BO_ 203 Duplicate: 1 ECU
      #| SG_ First M : 0|4@1+ (1,0) [0|15] "" Logger
      #| SG_ Second M : 4|4@1+ (1,0) [0|15] "" Logger
    ),
  )
  assert_eq(
    duplicate.database.decode_frame(203U, b"\x00"),
    Err(@moondbc.MultipleMultiplexers),
  )
}

///|
test "report unknown messages and short payloads" {
  let result = @moondbc.parse(
    (
      #|BO_ 204 Status: 2 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  assert_eq(
    result.database.decode_frame(999U, b"\x00\x00"),
    Err(@moondbc.UnknownMessage(999U)),
  )
  assert_eq(
    result.database.decode_frame(204U, b"\x00"),
    Err(@moondbc.PayloadTooShort(2, 1)),
  )
}

///|
test "identify the signal that failed to decode" {
  let result = @moondbc.parse(
    (
      #|BO_ 205 InvalidLayout: 1 ECU
      #| SG_ Outside : 8|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  assert_eq(
    result.database.decode_frame(205U, b"\x00"),
    Err(@moondbc.SignalDecodeFailed("Outside", @moondbc.FrameTooShort(16, 8))),
  )
}
