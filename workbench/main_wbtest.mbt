///|
test "workbench sample produces a source-aware multiplexed layout" {
  let parsed = @moondbc.parse_with_source_map(sample_dbc)
  assert_eq(parsed.diagnostics, [])
  assert_eq(parsed.database.messages.length(), 2)
  let layout = parsed.analyze_frame_layout(512U).unwrap()
  let shared = layout.find_cell(1, 0).unwrap()
  assert_eq(shared.kind, @moondbc.LayoutMultiplexed)
  assert_eq(shared.owners.length(), 2)
  assert_eq(shared.owners[0].source.unwrap().start_line, 16)
  assert_eq(shared.owners[1].source.unwrap().start_line, 17)
}

///|
test "local imports validate file metadata before reading" {
  assert_eq(validate_import_metadata("", -1), Some("No file was selected."))
  assert_eq(
    validate_import_metadata("network.txt", 128),
    Some("Choose a file with the .dbc extension."),
  )
  assert_eq(validate_import_metadata("network.DBC", max_import_bytes), None)
  assert_eq(
    validate_import_metadata("network.dbc", max_import_bytes + 1),
    Some("The file exceeds the 4 MiB import limit."),
  )
}

///|
test "workbench includes located semantic failures after parsing succeeds" {
  let parsed = @moondbc.parse_with_source_map(
    (
      #|BO_ 300 Status: 1 ECU
      #| SG_ First : 0|8@1+ (1,0) [0|255] "" ECU
      #| SG_ Second : 4|4@1+ (1,0) [0|15] "" ECU
    ),
  )
  assert_eq(parsed.diagnostics, [])
  let issues = workbench_validation_issues(parsed)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].source.unwrap().start_line, 3)
}

///|
test "workbench does not validate a partially parsed model" {
  let parsed = @moondbc.parse_with_source_map("BA_ \"Ignored\" BO_ 300 1;")
  assert_eq(parsed.diagnostics.length(), 1)
  assert_eq(workbench_validation_issues(parsed), [])
}

///|
test "workbench preview decodes the sample frame and candump record" {
  let parsed = @moondbc.parse_with_source_map(sample_dbc)
  let decoded = decode_preview(parsed, sample_frame).unwrap()
  assert_eq(decoded.name, "Powertrain")
  assert_eq(decoded.signals.length(), 3)
  assert_eq(decoded.signals[0].physical, 2000.0)
  assert_eq(decoded.signals[1].physical, 85.0)
  assert_eq(decoded.signals[2].physical, 1.0)
  let candump = decode_preview(
    parsed, "(1697042645.123456) can0 100#401F7D0100000000",
  ).unwrap()
  assert_eq(candump, decoded)
}

///|
test "workbench preview reports malformed and unmatched frames" {
  let parsed = @moondbc.parse_with_source_map(sample_dbc)
  assert_eq(
    decode_preview(parsed, ""),
    Err("Enter a SocketCAN frame or candump record."),
  )
  assert_eq(
    decode_preview(parsed, "bad frame"),
    Err("Invalid CAN record. Use 100#401F7D0100000000 or a candump line."),
  )
  assert_eq(
    decode_preview(parsed, "555#00"),
    Err("No DBC message matches standard CAN ID 1365."),
  )
  assert_eq(
    decode_preview(parsed, "100#00"),
    Err("Frame has 1 byte; the DBC message requires 8."),
  )
  let invalid = @moondbc.parse_with_source_map("BO_ invalid")
  assert_eq(
    decode_preview(invalid, sample_frame),
    Err("Fix DBC issues before decoding a frame."),
  )
}
