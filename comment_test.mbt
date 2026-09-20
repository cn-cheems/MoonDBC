///|
test "parse query and round trip DBC comments" {
  let source =
    #|CM_ "Vehicle database";
    #|CM_ BU_ ECU "Powertrain ECU";
    #|CM_ BO_ 100 "Status \"frame\"";
    #|CM_ SG_ 100 Speed "Path C:\\logs";
    #|BU_: ECU
    #|BO_ 100 Status: 2 ECU
    #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" ECU
  let result = @moondbc.parse(source)
  assert_eq(result.diagnostics, [])
  assert_eq(result.database.comments.length(), 4)
  assert_eq(result.database.database_comment(), Some("Vehicle database"))
  assert_eq(result.database.node_comment("ECU"), Some("Powertrain ECU"))
  assert_eq(result.database.message_comment(100U), Some("Status \"frame\""))
  assert_eq(
    result.database.signal_comment(100U, "Speed"),
    Some("Path C:\\logs"),
  )
  let written = result.database.to_dbc().unwrap()
  assert_eq(
    written,
    (
      #|BU_: ECU
      #|
      #|BO_ 100 Status: 2 ECU
      #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" ECU
      #|
      #|CM_ "Vehicle database";
      #|CM_ BU_ ECU "Powertrain ECU";
      #|CM_ BO_ 100 "Status \"frame\"";
      #|CM_ SG_ 100 Speed "Path C:\\logs";
    ),
  )
  let reparsed = @moondbc.parse(written)
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, result.database)
}

///|
test "diagnose invalid duplicate and unresolved DBC comments" {
  let source =
    #|BU_: ECU
    #|BO_ 100 Status: 1 ECU
    #| SG_ Speed : 0|8@1+ (1,0) [0|255] "" ECU
    #|CM_ BO_ bad "Invalid id";
    #|CM_ BU_ Missing "Unknown node";
    #|CM_ BO_ 999 "Unknown message";
    #|CM_ SG_ 100 Missing "Unknown signal";
    #|CM_ BO_ 100 "First";
    #|CM_ BO_ 100 "Second";
    #|CM_ EV_ Environment "Unsupported target";
    #|CM_ "Missing quote;
  let result = @moondbc.parse(source)
  let codes : Array[String] = []
  for diagnostic in result.diagnostics {
    codes.push(diagnostic.code)
  }
  assert_eq(codes, [
    "DBC011", "DBC011", "DBC011", "DBC012", "DBC013", "DBC014", "DBC015",
  ])
  assert_eq(result.database.comments, [
    { target: @moondbc.MessageComment(100U), text: "First", },
  ])
}

///|
test "validate comment references in manually built databases" {
  let database : @moondbc.Database = {
    version: None,
    nodes: ["ECU"],
    messages: [
      {
        id: 100U,
        name: "Status",
        payload_size: 1,
        transmitter: "ECU",
        additional_transmitters: [],
        signals: [
          {
            name: "Speed",
            start_bit: 0,
            bit_length: 8,
            byte_order: @moondbc.Intel,
            value_kind: @moondbc.Unsigned,
            value_type: @moondbc.Integer,
            factor: 1.0,
            offset: 0.0,
            minimum: 0.0,
            maximum: 255.0,
            unit: "",
            receivers: ["ECU"],
            multiplex: @moondbc.Plain,
          },
        ],
      },
    ],
    value_tables: [],
    comments: [
      { target: @moondbc.DatabaseComment, text: "First", },
      { target: @moondbc.DatabaseComment, text: "Second", },
      { target: @moondbc.NodeComment("Missing"), text: "Unknown", },
      { target: @moondbc.MessageComment(999U), text: "Unknown", },
      { target: @moondbc.SignalComment(100U, "Missing"), text: "Unknown", },
      { target: @moondbc.SignalComment(999U, "Speed"), text: "Unknown", },
    ],
  }
  assert_eq(database.validate(), [
    @moondbc.DuplicateCommentIssue(@moondbc.DatabaseComment),
    @moondbc.UnknownCommentNodeIssue("Missing"),
    @moondbc.UnknownCommentMessageIssue(999U),
    @moondbc.UnknownCommentSignalIssue(100U, "Missing"),
    @moondbc.UnknownCommentMessageIssue(999U),
  ])
}

///|
test "reject multiline comments during DBC export" {
  let database : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [],
    value_tables: [],
    comments: [{ target: @moondbc.DatabaseComment, text: "first\nsecond", }],
  }
  assert_eq(
    database.to_dbc(),
    Err(@moondbc.DbcWriteInvalidQuotedText("comment", "first\nsecond")),
  )
}
