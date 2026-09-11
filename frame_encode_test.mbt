///|
test "encode a complete frame from named physical values" {
  let database = @moondbc.parse(
      (
        #|BO_ 800 Powertrain: 3 ECU
        #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
        #| SG_ Gear : 16|8@1+ (1,0) [0|7] "" Dashboard
      ),
    ).database
  let assignments : Array[@moondbc.SignalAssignment] = [
    { name: "Gear", physical: 1.0, },
    { name: "EngineSpeed", physical: 1000.0, },
  ]
  let payload = database.encode_frame(800U, assignments).unwrap()
  assert_eq(payload, b"\x40\x1f\x01")
  let decoded = database.decode_frame(800U, payload).unwrap()
  assert_eq(decoded.signals[0].physical, 1000.0)
  assert_eq(decoded.signals[1].physical, 1.0)
}

///|
test "encode only the active multiplex branch" {
  let message = @moondbc.parse(
      (
        #|BO_ 801 Sensor: 2 ECU
        #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" Logger
        #| SG_ Voltage m1 : 8|8@1+ (0.5,0) [0|127.5] "V" Logger
        #| SG_ Current m2 : 8|8@1+ (0.25,0) [0|63.75] "A" Logger
      ),
    ).database.messages[0]
  assert_eq(
    message.encode_frame([
      { name: "Mode", physical: 1.0, },
      { name: "Voltage", physical: 5.0, },
    ]),
    Ok(b"\x01\x0a"),
  )
  assert_eq(
    message.encode_frame([
      { name: "Mode", physical: 2.0, },
      { name: "Current", physical: 3.0, },
    ]),
    Ok(b"\x02\x0c"),
  )
}

///|
test "reject missing and inactive multiplex assignments" {
  let message = @moondbc.parse(
      (
        #|BO_ 802 Sensor: 2 ECU
        #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" Logger
        #| SG_ Voltage m1 : 8|8@1+ (0.5,0) [0|127.5] "V" Logger
        #| SG_ Current m2 : 8|8@1+ (0.25,0) [0|63.75] "A" Logger
      ),
    ).database.messages[0]
  assert_eq(
    message.encode_frame([{ name: "Mode", physical: 1.0, }]),
    Err(@moondbc.FrameEncodeMissingSignal("Voltage")),
  )
  assert_eq(
    message.encode_frame([
      { name: "Mode", physical: 1.0, },
      { name: "Voltage", physical: 5.0, },
      { name: "Current", physical: 3.0, },
    ]),
    Err(@moondbc.FrameEncodeInactiveSignal("Current", 2)),
  )
}

///|
test "reject unknown duplicate and missing signal assignments" {
  let message = @moondbc.parse(
      (
        #|BO_ 803 Status: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|255] "" Logger
      ),
    ).database.messages[0]
  assert_eq(
    message.encode_frame([{ name: "Unknown", physical: 0.0, }]),
    Err(@moondbc.FrameEncodeUnknownSignal("Unknown")),
  )
  assert_eq(
    message.encode_frame([
      { name: "State", physical: 1.0, },
      { name: "State", physical: 2.0, },
    ]),
    Err(@moondbc.FrameEncodeDuplicateSignal("State")),
  )
  assert_eq(
    message.encode_frame([]),
    Err(@moondbc.FrameEncodeMissingSignal("State")),
  )
}

///|
test "identify the signal when physical encoding fails" {
  let message = @moondbc.parse(
      (
        #|BO_ 804 Status: 1 ECU
        #| SG_ Level : 0|8@1+ (1,0) [0|100] "percent" Logger
      ),
    ).database.messages[0]
  assert_eq(
    message.encode_frame([{ name: "Level", physical: 101.0, }]),
    Err(
      @moondbc.FrameSignalEncodeFailed(
        "Level",
        @moondbc.PhysicalValueOutOfRange(101.0, 0.0, 100.0),
      ),
    ),
  )
}

///|
test "report invalid multiplex layouts during frame encoding" {
  let missing = @moondbc.parse(
      (
        #|BO_ 805 Missing: 1 ECU
        #| SG_ Branch m1 : 0|8@1+ (1,0) [0|255] "" Logger
      ),
    ).database.messages[0]
  assert_eq(
    missing.encode_frame([{ name: "Branch", physical: 1.0, }]),
    Err(@moondbc.FrameEncodeMissingMultiplexer),
  )
  let duplicate = @moondbc.parse(
      (
        #|BO_ 806 Duplicate: 1 ECU
        #| SG_ First M : 0|4@1+ (1,0) [0|15] "" Logger
        #| SG_ Second M : 4|4@1+ (1,0) [0|15] "" Logger
      ),
    ).database.messages[0]
  assert_eq(
    duplicate.encode_frame([
      { name: "First", physical: 1.0, },
      { name: "Second", physical: 2.0, },
    ]),
    Err(@moondbc.FrameEncodeMultipleMultiplexers),
  )
}

///|
test "report unknown messages and invalid payload sizes during encoding" {
  let database = @moondbc.parse("").database
  assert_eq(
    database.encode_frame(999U, []),
    Err(@moondbc.FrameEncodeUnknownMessage(999U)),
  )
  let invalid : @moondbc.Message = {
    id: 807U,
    name: "Invalid",
    payload_size: -1,
    transmitter: "ECU",
    signals: [],
  }
  assert_eq(
    invalid.encode_frame([]),
    Err(@moondbc.FrameEncodeInvalidPayloadSize(-1)),
  )
}
