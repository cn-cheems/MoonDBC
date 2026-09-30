///|
test "parse, look up, and write DBC signal groups" {
  let source =
    #|BU_: ECU Dashboard
    #|
    #|BO_ 420 Measurement: 2 ECU
    #| SG_ Voltage : 0|8@1+ (0.5,0) [0|127.5] "V" Dashboard
    #| SG_ Current : 8|8@1+ (0.25,0) [0|63.75] "A" Dashboard
    #|SIG_GROUP_ 420 Electrical 0 : Voltage, Current;
  let parsed = @moondbc.parse(source)
  assert_eq(parsed.diagnostics, [])
  let group = parsed.database.find_signal_group(420U, "Electrical").unwrap()
  assert_eq(group.repetition, 0)
  assert_eq(group.signals, ["Voltage", "Current"])
  let written = parsed.database.to_dbc().unwrap()
  assert_eq(
    written,
    (
      #|BU_: ECU Dashboard
      #|
      #|BO_ 420 Measurement: 2 ECU
      #| SG_ Voltage : 0|8@1+ (0.5,0) [0|127.5] "V" Dashboard
      #| SG_ Current : 8|8@1+ (0.25,0) [0|63.75] "A" Dashboard
      #|SIG_GROUP_ 420 Electrical 0 : Voltage Current;
    ),
  )
  let reparsed = @moondbc.parse(written)
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, parsed.database)
}

///|
test "signal groups report malformed and unresolved references" {
  let malformed = @moondbc.parse("SIG_GROUP_ 420 Electrical -1 : Voltage;")
  assert_eq(malformed.diagnostics, [
    {
      line: 1,
      column: 1,
      code: "DBC043",
      message: "signal group repetition must be a nonnegative integer",
    },
  ])
  let unresolved = @moondbc.parse(
    (
      #|BO_ 421 Status: 1 ECU
      #| SG_ Ready : 0|1@1+ (1,0) [0|1] "" Dashboard
      #|SIG_GROUP_ 421 Summary 1 : Missing;
      #|SIG_GROUP_ 422 Other 1 : Ready;
    ),
  )
  assert_eq(unresolved.diagnostics, [
    {
      line: 3,
      column: 1,
      code: "DBC046",
      message: "signal group refers to an unknown signal",
    },
    {
      line: 4,
      column: 1,
      code: "DBC044",
      message: "signal group refers to an unknown message",
    },
  ])
}

///|
test "signal group changes retain source locations" {
  let before = @moondbc.parse_with_source_map(
    (
      #|BO_ 423 Status: 1 ECU
      #| SG_ Ready : 0|1@1+ (1,0) [0|1] "" Dashboard
      #|SIG_GROUP_ 423 Summary 1 : Ready;
    ),
  )
  let after = @moondbc.parse_with_source_map(
    (
      #|BO_ 423 Status: 1 ECU
      #| SG_ Ready : 0|1@1+ (1,0) [0|1] "" Dashboard
      #|SIG_GROUP_ 423 Summary 2 : Ready;
    ),
  )
  assert_eq(
    before.source_map.find_signal_group(423U, "Summary").unwrap().start_line,
    3,
  )
  let changes = before.diff_with_locations(after)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].before.unwrap().start_line, 3)
  assert_eq(changes[0].after.unwrap().start_line, 3)
  assert_eq(changes[0].change.impact(), @moondbc.Breaking)
}

///|
test "validate manually constructed signal groups" {
  let database : @moondbc.Database = {
    version: None,
    nodes: ["ECU"],
    messages: [
      {
        id: 422U,
        name: "Status",
        payload_size: 1,
        transmitter: "ECU",
        additional_transmitters: [],
        signals: [],
      },
    ],
    value_tables: [],
    global_value_tables: [],
    signal_groups: [
      { message_id: 422U, name: "", repetition: 0, signals: [], },
      { message_id: 422U, name: "State", repetition: 1, signals: ["Missing"], },
      { message_id: 422U, name: "State", repetition: 1, signals: [], },
    ],
    comments: [],
    attributes: @moondbc.DbcAttributes::empty(),
  }
  assert_eq(database.validate(), [
    @moondbc.InvalidSignalGroupIssue(422U, ""),
    @moondbc.UnknownSignalGroupMemberIssue(422U, "State", "Missing"),
    @moondbc.DuplicateSignalGroupIssue(422U, "State"),
    @moondbc.InvalidSignalGroupIssue(422U, "State"),
  ])
}
