///|
fn extended_multiplex_source() -> String {
  (
    #|SG_MUL_VAL_ 700 First Mode 1-3, 7-9;
    #|SG_MUL_VAL_ 700 Second Mode 4-6;
    #|BO_ 700 Sensor: 2 ECU
    #| SG_ Mode M : 0|8@1+ (1,0) [0|9] "" Logger
    #| SG_ First m1 : 8|8@1+ (1,0) [0|255] "" Logger
    #| SG_ Second m4 : 8|8@1+ (1,0) [0|255] "" Logger
  )
}

///|
test "resolve extended multiplex ranges before their message" {
  let parsed = @moondbc.parse(extended_multiplex_source())
  assert_eq(parsed.diagnostics, [])
  let message = parsed.database.messages[0]
  assert_eq(
    message.find_signal("First").unwrap().multiplex,
    @moondbc.MultiplexedRanges("Mode", [
      { start: 1, end: 3, },
      { start: 7, end: 9, },
    ]),
  )
  assert_eq(parsed.database.validate(), [])
}

///|
test "encode and decode every active extended multiplex branch" {
  let message = @moondbc.parse(extended_multiplex_source()).database.messages[0]
  for selector in [1, 3, 7, 9] {
    let payload = message
      .encode_frame([
        { name: "Mode", physical: selector.to_double(), },
        { name: "First", physical: 42.0, },
      ])
      .unwrap()
    let decoded = message.decode_frame(payload).unwrap()
    assert_eq(decoded.signals.length(), 2)
    assert_eq(decoded.signals[1].name, "First")
    assert_eq(decoded.signals[1].physical, 42.0)
  }
  for selector in [4, 5, 6] {
    let payload = message
      .encode_frame([
        { name: "Mode", physical: selector.to_double(), },
        { name: "Second", physical: 42.0, },
      ])
      .unwrap()
    assert_eq(payload[0], selector.to_byte())
    let decoded = message.decode_frame(payload).unwrap()
    assert_eq(decoded.signals[1].name, "Second")
  }
  assert_eq(message.decode_frame(b"\x00\x2a").unwrap().signals.length(), 1)
  assert_eq(
    message.encode_frame([
      { name: "Mode", physical: 2.0, },
      { name: "First", physical: 42.0, },
      { name: "Second", physical: 42.0, },
    ]),
    Err(@moondbc.FrameEncodeInactiveRangeSignal("Second")),
  )
  assert_eq(
    message.encode_frame([{ name: "Mode", physical: 2.0, }]),
    Err(@moondbc.FrameEncodeMissingSignal("First")),
  )
}

///|
test "report extended multiplex conflicts only for intersecting selectors" {
  let parsed = @moondbc.parse_with_source_map(extended_multiplex_source())
  let layout = parsed.analyze_frame_layout(700U).unwrap()
  assert_eq(layout.issues, [])
  assert_eq(layout.cells[8].kind, @moondbc.LayoutMultiplexed)
  let conflicting = @moondbc.parse_with_source_map(
    (
      #|BO_ 701 Sensor: 2 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|9] "" Logger
      #| SG_ First m1 : 8|8@1+ (1,0) [0|255] "" Logger
      #| SG_ Second m3 : 8|8@1+ (1,0) [0|255] "" Logger
      #|SG_MUL_VAL_ 701 First Mode 1-3;
      #|SG_MUL_VAL_ 701 Second Mode 3-6;
    ),
  )
  assert_eq(conflicting.database.validate(), [
    @moondbc.OverlappingSignalsIssue(701U, "First", "Second"),
  ])
  assert_eq(
    conflicting.analyze_frame_layout(701U).unwrap().cells[8].kind,
    @moondbc.LayoutConflict,
  )
}

///|
test "preserve extended multiplex ranges through DBC and generated metadata" {
  let parsed = @moondbc.parse(extended_multiplex_source())
  let written = parsed.database.to_dbc().unwrap()
  assert_true(written.contains("SG_MUL_VAL_ 700 First Mode 1-3, 7-9;"))
  assert_eq(@moondbc.parse(written).database, parsed.database)
  let formatted = @moondbc.run_format_cli(
    "sensor.dbc",
    extended_multiplex_source(),
    false,
  )
  assert_eq(formatted.exit_code, 0)
  assert_eq(@moondbc.parse(formatted.stdout).database, parsed.database)
  let generated = parsed.database.generate_moonbit_constants()
  assert_true(generated.contains("MULTIPLEX_RANGE_1_END : Int = 9"))
}

///|
test "diagnose malformed and unresolved extended multiplex declarations" {
  let parsed = @moondbc.parse(
    (
      #|BO_ 702 Sensor: 2 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|9] "" Logger
      #| SG_ First m1 : 8|8@1+ (1,0) [0|255] "" Logger
      #|SG_MUL_VAL_ 702 First Mode 3-1;
      #|SG_MUL_VAL_ 999 First Mode 1-2;
      #|SG_MUL_VAL_ 702 Missing Mode 1-2;
      #|SG_MUL_VAL_ 702 First Other 1-2;
    ),
  )
  assert_eq(parsed.diagnostics.length(), 4)
  assert_eq(parsed.diagnostics[0].code, "DBC024")
  assert_eq(parsed.diagnostics[1].code, "DBC025")
  assert_eq(parsed.diagnostics[2].code, "DBC026")
  assert_eq(parsed.diagnostics[3].code, "DBC028")
}

///|
test "validate selector width and repeated extended multiplex declarations" {
  let parsed = @moondbc.parse(
    (
      #|BO_ 703 Sensor: 2 ECU
      #| SG_ Mode M : 0|2@1+ (1,0) [0|3] "" Logger
      #| SG_ First m1 : 8|8@1+ (1,0) [0|255] "" Logger
      #|SG_MUL_VAL_ 703 First Mode 1-4;
      #|SG_MUL_VAL_ 703 First Mode 2-3;
    ),
  )
  assert_eq(parsed.diagnostics.length(), 1)
  assert_eq(parsed.diagnostics[0].line, 5)
  assert_eq(parsed.diagnostics[0].code, "DBC027")
  assert_eq(parsed.database.validate(), [
    @moondbc.MultiplexSelectorOutOfRangeIssue(703U, "First", 4),
  ])
}

///|
test "detect a basic branch overlapping an extended selector range" {
  let parsed = @moondbc.parse(
    (
      #|BO_ 704 Sensor: 2 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|9] "" Logger
      #| SG_ First m2 : 8|8@1+ (1,0) [0|255] "" Logger
      #| SG_ Second m1 : 8|8@1+ (1,0) [0|255] "" Logger
      #|SG_MUL_VAL_ 704 Second Mode 1-3;
    ),
  )
  assert_eq(parsed.diagnostics, [])
  assert_eq(parsed.database.validate(), [
    @moondbc.OverlappingSignalsIssue(704U, "First", "Second"),
  ])
}
