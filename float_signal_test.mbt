///|
test "parse deferred IEEE-754 signal value types" {
  let result = @moondbc.parse(
    (
      #|SIG_VALTYPE_ 700 Temperature : 1;
      #|SIG_VALTYPE_ 700 Energy : 2;
      #|BO_ 700 Measurements: 12 ECU
      #| SG_ Temperature : 0|32@1+ (1,0) [-1000|1000] "degC" Logger
      #| SG_ Energy : 32|64@1+ (1,0) [-1000000|1000000] "J" Logger
    ),
  )
  assert_eq(result.diagnostics, [])
  let message = result.database.messages[0]
  assert_eq(message.signals[0].value_type, @moondbc.Float32)
  assert_eq(message.signals[1].value_type, @moondbc.Float64)
}

///|
test "report malformed and unresolved signal value types" {
  let result = @moondbc.parse(
    (
      #|SIG_VALTYPE_ 10 Present : 9;
      #|SIG_VALTYPE_ 99 Unknown : 1;
      #|BO_ 10 Measurements: 4 ECU
      #| SG_ Present : 0|32@1+ (1,0) [-1000|1000] "" Logger
      #|SIG_VALTYPE_ 10 Missing : 2;
      #|SIG_VALTYPE_ 10 Present : 1;
      #|SIG_VALTYPE_ 10 Present : 2;
    ),
  )
  assert_eq(result.diagnostics.length(), 4)
  assert_eq(result.diagnostics[0].code, "DBC020")
  assert_eq(result.diagnostics[1].code, "DBC021")
  assert_eq(result.diagnostics[2].code, "DBC022")
  assert_eq(result.diagnostics[3].code, "DBC023")
}

///|
test "decode and encode scaled Intel Float32 signal" {
  let signal = @moondbc.parse(
      (
        #|BO_ 701 Measurements: 4 ECU
        #| SG_ Temperature : 0|32@1+ (2,1) [-1000|1000] "degC" Logger
        #|SIG_VALTYPE_ 701 Temperature : 1;
      ),
    ).database.messages[0].signals[0]
  let payload = b"\x00\x00\xc0\x3f"
  assert_eq(signal.decode_raw(payload), Ok(@moondbc.FloatRaw(1.5)))
  assert_eq(signal.decode(payload), Ok(4.0))
  assert_eq(signal.encode(b"\x00\x00\x00\x00", 4.0), Ok(payload))
  assert_eq(
    signal.encode_raw(b"\x00\x00\x00\x00", @moondbc.FloatRaw(1.5)),
    Ok(payload),
  )
}

///|
test "decode and encode Intel Float64 and Motorola Float32 signals" {
  let intel = @moondbc.parse(
      (
        #|BO_ 702 Measurements: 8 ECU
        #| SG_ Energy : 0|64@1+ (1,0) [-1000|1000] "J" Logger
        #|SIG_VALTYPE_ 702 Energy : 2;
      ),
    ).database.messages[0].signals[0]
  let double_payload = b"\x00\x00\x00\x00\x00\x00\xf8\x3f"
  assert_eq(intel.decode_raw(double_payload), Ok(@moondbc.FloatRaw(1.5)))
  assert_eq(
    intel.encode_raw(
      b"\x00\x00\x00\x00\x00\x00\x00\x00",
      @moondbc.FloatRaw(1.5),
    ),
    Ok(double_payload),
  )
  let motorola = @moondbc.parse(
      (
        #|BO_ 703 Measurements: 4 ECU
        #| SG_ Temperature : 7|32@0+ (1,0) [-1000|1000] "degC" Logger
        #|SIG_VALTYPE_ 703 Temperature : 1;
      ),
    ).database.messages[0].signals[0]
  let float_payload = b"\x3f\xc0\x00\x00"
  assert_eq(motorola.decode(float_payload), Ok(1.5))
  assert_eq(
    motorola.encode_raw(b"\x00\x00\x00\x00", @moondbc.FloatRaw(1.5)),
    Ok(float_payload),
  )
}

///|
test "validate floating signal width and multiplex selector" {
  let database = @moondbc.parse(
      (
        #|BO_ 704 Invalid: 8 ECU
        #| SG_ Mode M : 0|16@1+ (1,0) [0|10] "" Logger
        #|SIG_VALTYPE_ 704 Mode : 1;
      ),
    ).database
  assert_eq(database.validate(), [
    @moondbc.InvalidSignalValueTypeIssue(704U, "Mode", @moondbc.Float32, 16),
    @moondbc.FloatingMultiplexerIssue(704U, "Mode", @moondbc.Float32),
  ])
}

///|
test "write and generate floating signal metadata" {
  let source =
    #|BO_ 705 Measurements: 8 ECU
    #| SG_ Energy : 0|64@1+ (1,0) [-1000|1000] "J" Logger
    #|SIG_VALTYPE_ 705 Energy : 2;
  let original = @moondbc.parse(source)
  let written = original.database.to_dbc().unwrap()
  assert_eq(
    written,
    (
      #|BU_:
      #|
      #|BO_ 705 Measurements: 8 ECU
      #| SG_ Energy : 0|64@1+ (1,0) [-1000|1000] "J" Logger
      #|
      #|SIG_VALTYPE_ 705 Energy : 2;
    ),
  )
  assert_eq(@moondbc.parse(written).database, original.database)
  assert_true(
    original.database
    .generate_moonbit_constants()
    .find("pub const DBC_MEASUREMENTS_705_ENERGY_0_IS_FLOAT64 : Bool = true")
    is Some(_),
  )
}

///|
test "classify a signal value type change as breaking" {
  let integer = @moondbc.parse(
      (
        #|BO_ 706 Measurements: 4 ECU
        #| SG_ Reading : 0|32@1+ (1,0) [-1000|1000] "" Logger
      ),
    ).database
  let floating = @moondbc.parse(
      (
        #|BO_ 706 Measurements: 4 ECU
        #| SG_ Reading : 0|32@1+ (1,0) [-1000|1000] "" Logger
        #|SIG_VALTYPE_ 706 Reading : 1;
      ),
    ).database
  let report = integer.compatibility_report(floating)
  assert_eq(report.breaking_count, 1)
  assert_eq(report.changes[0].impact, @moondbc.Breaking)
}
