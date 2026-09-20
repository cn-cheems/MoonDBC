///|
test "retain declaration source ranges without changing parse results" {
  let message_line = "BO_ 100 Status: 2 ECU"
  let signal_line = "SG_ State : 0|8@1+ (1,0) [0|255] \"\" Logger"
  let source = "  " + message_line + "  \r\n   " + signal_line + "  \r\n"
  let located = @moondbc.parse_with_source_map(source)
  let plain = @moondbc.parse(source)
  assert_eq(located.database, plain.database)
  assert_eq(located.diagnostics, plain.diagnostics)
  assert_eq(
    located.source_map.find_message(100U),
    Some({
      start_line: 1,
      start_column: 3,
      end_line: 1,
      end_column: 3 + message_line.length(),
    }),
  )
  assert_eq(
    located.source_map.find_signal(100U, "State"),
    Some({
      start_line: 2,
      start_column: 4,
      end_line: 2,
      end_column: 4 + signal_line.length(),
    }),
  )
  assert_eq(located.source_map.find_signal(100U, "Missing"), None)
}

///|
test "map Intel and Motorola raw bits to payload cells" {
  let parsed = @moondbc.parse_with_source_map(
    (
      #|BO_ 101 Layout: 2 ECU
      #| SG_ IntelLow : 0|4@1+ (1,0) [0|15] "" Logger
      #| SG_ MotorolaByte : 15|8@0+ (1,0) [0|255] "" Logger
    ),
  )
  let layout = parsed.analyze_frame_layout(101U).unwrap()
  assert_eq(layout.cells.length(), 16)
  assert_eq(layout.issues, [])
  let intel_lsb = layout.find_cell(0, 0).unwrap()
  assert_eq(intel_lsb.kind, @moondbc.LayoutOccupied)
  assert_eq(intel_lsb.owners[0].signal_name, "IntelLow")
  assert_eq(intel_lsb.owners[0].signal_bit, 0)
  assert_eq(intel_lsb.owners[0].source.unwrap().start_line, 2)
  assert_eq(layout.find_cell(0, 4).unwrap().kind, @moondbc.LayoutUnused)
  let motorola_msb = layout.find_cell(1, 7).unwrap()
  assert_eq(motorola_msb.owners[0].signal_name, "MotorolaByte")
  assert_eq(motorola_msb.owners[0].signal_bit, 7)
  assert_eq(layout.find_cell(1, 0).unwrap().owners[0].signal_bit, 0)
  assert_eq(layout.find_cell(2, 0), None)
  assert_eq(layout.find_cell(2147483647, 0), None)
}

///|
test "distinguish exclusive multiplex sharing from conflicts" {
  let multiplexed = @moondbc.parse_with_source_map(
      (
        #|BO_ 102 Multiplexed: 2 ECU
        #| SG_ Mode M : 0|4@1+ (1,0) [0|2] "" Logger
        #| SG_ First m1 : 8|8@1+ (1,0) [0|255] "" Logger
        #| SG_ Second m2 : 8|8@1+ (1,0) [0|255] "" Logger
      ),
    )
    .analyze_frame_layout(102U)
    .unwrap()
  assert_eq(multiplexed.issues, [])
  assert_eq(multiplexed.cells[8].kind, @moondbc.LayoutMultiplexed)
  assert_eq(multiplexed.cells[8].owners.length(), 2)

  let parsed = @moondbc.parse_with_source_map(
    (
      #|BO_ 103 Conflict: 2 ECU
      #| SG_ First : 0|8@1+ (1,0) [0|255] "" Logger
      #| SG_ Second : 4|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  let conflicting = parsed.analyze_frame_layout(103U).unwrap()
  assert_eq(conflicting.cells[4].kind, @moondbc.LayoutConflict)
  let first_source = parsed.source_map.find_signal(103U, "First")
  let second_source = parsed.source_map.find_signal(103U, "Second")
  assert_eq(conflicting.issues, [
    @moondbc.LayoutConflictingSignals(
      "First",
      "Second",
      [4, 5, 6, 7],
      first_source,
      second_source,
    ),
  ])
}

///|
test "report out of payload signals with their source range" {
  let parsed = @moondbc.parse_with_source_map(
    (
      #|BO_ 104 Small: 1 ECU
      #| SG_ TooFar : 8|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  let source = parsed.source_map.find_signal(104U, "TooFar")
  assert_eq(parsed.analyze_frame_layout(104U).unwrap().issues, [
    @moondbc.LayoutSignalOutsidePayload("TooFar", source),
  ])
  assert_eq(parsed.database.analyze_frame_layout(104U).unwrap().issues, [
    @moondbc.LayoutSignalOutsidePayload("TooFar", None),
  ])
  assert_eq(
    parsed.analyze_frame_layout(999U),
    Err(@moondbc.LayoutUnknownMessage(999U)),
  )
}

///|
test "report invalid manually constructed layout metadata" {
  let signal : @moondbc.Signal = {
    name: "Broken",
    start_bit: -1,
    bit_length: 0,
    byte_order: @moondbc.Intel,
    value_kind: @moondbc.Unsigned,
    value_type: @moondbc.Integer,
    factor: 1.0,
    offset: 0.0,
    minimum: 0.0,
    maximum: 0.0,
    unit: "",
    receivers: [],
    multiplex: @moondbc.Plain,
  }
  let database : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [
      {
        id: 105U,
        name: "Manual",
        payload_size: 1,
        transmitter: "ECU",
        additional_transmitters: [],
        signals: [signal],
      },
    ],
    value_tables: [],
    comments: [],
  }
  assert_eq(database.analyze_frame_layout(105U).unwrap().issues, [
    @moondbc.LayoutInvalidSignal("Broken", -1, 0, None),
  ])
}

///|
test "analyze the full CAN FD payload boundary" {
  let layout = @moondbc.parse_with_source_map(
      (
        #|BO_ 106 FullFd: 64 ECU
        #| SG_ First : 0|1@1+ (1,0) [0|1] "" Logger
        #| SG_ Last : 511|1@1+ (1,0) [0|1] "" Logger
      ),
    )
    .analyze_frame_layout(106U)
    .unwrap()
  assert_eq(layout.cells.length(), 512)
  assert_eq(layout.issues, [])
  assert_eq(layout.find_cell(0, 0).unwrap().owners[0].signal_name, "First")
  assert_eq(layout.find_cell(63, 7).unwrap().owners[0].signal_name, "Last")
}
