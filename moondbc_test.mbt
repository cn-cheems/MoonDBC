///|
test "parse database, message, and signals" {
  let source =
    #|VERSION "1.0"
    #|BU_: ECU Dashboard
    #|BO_ 256 Powertrain: 8 ECU
    #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
    #| SG_ CoolantTemp : 23|8@0- (1,-40) [-40|215] "degC" Dashboard
  let result = @moondbc.parse(source)
  assert_true(result.is_valid())
  assert_eq(result.database.version, Some("1.0"))
  assert_eq(result.database.nodes, ["ECU", "Dashboard"])
  let message = result.database.find_message(256U).unwrap()
  assert_eq(message.name, "Powertrain")
  assert_eq(message.payload_size, 8)
  assert_eq(message.transmitter, "ECU")
  assert_eq(message.signals.length(), 2)
  let speed = message.find_signal("EngineSpeed").unwrap()
  assert_eq(speed.start_bit, 0)
  assert_eq(speed.bit_length, 16)
  assert_eq(speed.byte_order, @moondbc.Intel)
  assert_eq(speed.value_kind, @moondbc.Unsigned)
  assert_eq(speed.factor, 0.125)
  assert_eq(speed.unit, "rpm")
  assert_eq(speed.receivers, ["Dashboard"])
  let temperature = message.find_signal("CoolantTemp").unwrap()
  assert_eq(temperature.byte_order, @moondbc.Motorola)
  assert_eq(temperature.value_kind, @moondbc.Signed)
  assert_eq(temperature.offset, -40.0)
}

///|
test "parse multiplexing markers" {
  let source =
    #|BO_ 512 SensorData: 8 Sensor
    #| SG_ Mode M : 0|4@1+ (1,0) [0|15] "" Controller
    #| SG_ Voltage m1 : 8|16@1+ (0.01,0) [0|655.35] "V" Controller
  let result = @moondbc.parse(source)
  assert_true(result.is_valid())
  let message = result.database.find_message(512U).unwrap()
  assert_eq(
    message.find_signal("Mode").unwrap().multiplex,
    @moondbc.Multiplexer,
  )
  assert_eq(
    message.find_signal("Voltage").unwrap().multiplex,
    @moondbc.Multiplexed(1),
  )
}

///|
test "report malformed and misplaced declarations" {
  let source =
    #|SG_ Orphan : 0|8@1+ (1,0) [0|255] "" ECU
    #|BO_ invalid Broken: 100 ECU
    #|BO_ 42 Valid: 8 ECU
    #| SG_ BadRange : 0|8@1+ (1,0) [10|0] "" ECU
  let result = @moondbc.parse(source)
  assert_false(result.is_valid())
  assert_eq(result.diagnostics.length(), 3)
  assert_eq(result.diagnostics[0].code, "DBC004")
  assert_eq(result.diagnostics[1].code, "DBC002")
  assert_eq(result.diagnostics[2].code, "DBC005")
}

///|
test "report duplicate ids and signal names" {
  let source =
    #|BO_ 10 First: 8 ECU
    #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
    #| SG_ State : 8|8@1+ (1,0) [0|255] "" ECU
    #|BO_ 10 Second: 8 ECU
  let result = @moondbc.parse(source)
  assert_eq(result.diagnostics.length(), 2)
  assert_eq(result.diagnostics[0].code, "DBC006")
  assert_eq(result.diagnostics[1].code, "DBC003")
}
