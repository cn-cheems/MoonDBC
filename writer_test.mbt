///|
test "write canonical DBC text and preserve the database" {
  let source =
    #|VERSION "2.1"
    #|BU_: ECU Dashboard Logger
    #|BO_ 900 Powertrain: 4 ECU
    #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" Dashboard,Logger
    #| SG_ Torque m1 : 8|16@1- (0.5,-10) [-10|100] "Nm" Dashboard
    #|BO_ 901 Status: 1 ECU
    #| SG_ Ready : 7|1@0+ (1,0) [0|1] "" Logger
    #|VAL_ 900 Mode 0 "Off" 1 "Drive mode";
  let original = @moondbc.parse(source)
  assert_eq(original.diagnostics, [])
  let written = original.database.to_dbc().unwrap()
  assert_eq(
    written,
    (
      #|VERSION "2.1"
      #|
      #|BU_: ECU Dashboard Logger
      #|
      #|BO_ 900 Powertrain: 4 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" Dashboard,Logger
      #| SG_ Torque m1 : 8|16@1- (0.5,-10) [-10|100] "Nm" Dashboard
      #|
      #|BO_ 901 Status: 1 ECU
      #| SG_ Ready : 7|1@0+ (1,0) [0|1] "" Logger
      #|
      #|VAL_ 900 Mode 0 "Off" 1 "Drive mode";
    ),
  )
  let reparsed = @moondbc.parse(written)
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, original.database)
}

///|
test "write an empty database with an explicit node declaration" {
  let database : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [],
    value_tables: [],
  }
  assert_eq(database.to_dbc(), Ok("BU_:"))
  let reparsed = @moondbc.parse(database.to_dbc().unwrap())
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, database)
}

///|
test "reject tokens and quoted text that cannot round trip" {
  let invalid_node : @moondbc.Database = {
    version: None,
    nodes: ["Body ECU"],
    messages: [],
    value_tables: [],
  }
  assert_eq(
    invalid_node.to_dbc(),
    Err(@moondbc.DbcWriteInvalidToken("node name", "Body ECU")),
  )
  let invalid_version : @moondbc.Database = {
    version: Some("release \"candidate\""),
    nodes: [],
    messages: [],
    value_tables: [],
  }
  assert_eq(
    invalid_version.to_dbc(),
    Err(
      @moondbc.DbcWriteInvalidQuotedText(
        "database version", "release \"candidate\"",
      ),
    ),
  )
}

///|
test "reject invalid message and signal values" {
  let signal : @moondbc.Signal = {
    name: "Level",
    start_bit: 0,
    bit_length: 8,
    byte_order: @moondbc.Intel,
    value_kind: @moondbc.Unsigned,
    factor: 0.0 / 0.0,
    offset: 0.0,
    minimum: 0.0,
    maximum: 100.0,
    unit: "percent",
    receivers: ["Logger"],
    multiplex: @moondbc.Plain,
  }
  let database : @moondbc.Database = {
    version: None,
    nodes: ["ECU"],
    messages: [
      {
        id: 902U,
        name: "Status",
        payload_size: 1,
        transmitter: "ECU",
        signals: [signal],
      },
    ],
    value_tables: [],
  }
  assert_eq(
    database.to_dbc(),
    Err(@moondbc.DbcWriteNonFiniteSignalNumber(902U, "Level", "factor")),
  )
  let invalid_size : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [
      {
        id: 903U,
        name: "Status",
        payload_size: 65,
        transmitter: "ECU",
        signals: [],
      },
    ],
    value_tables: [],
  }
  assert_eq(
    invalid_size.to_dbc(),
    Err(@moondbc.DbcWriteInvalidPayloadSize(903U, 65)),
  )
}

///|
test "reject invalid multiplex values and empty value tables" {
  let signal : @moondbc.Signal = {
    name: "Branch",
    start_bit: 0,
    bit_length: 8,
    byte_order: @moondbc.Intel,
    value_kind: @moondbc.Unsigned,
    factor: 1.0,
    offset: 0.0,
    minimum: 0.0,
    maximum: 255.0,
    unit: "",
    receivers: [],
    multiplex: @moondbc.Multiplexed(-1),
  }
  let invalid_multiplex : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [
      {
        id: 904U,
        name: "Status",
        payload_size: 1,
        transmitter: "ECU",
        signals: [signal],
      },
    ],
    value_tables: [],
  }
  assert_eq(
    invalid_multiplex.to_dbc(),
    Err(@moondbc.DbcWriteNegativeMultiplexValue(904U, "Branch", -1)),
  )
  let empty_table : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [],
    value_tables: [{ message_id: 905U, signal_name: "State", entries: [], }],
  }
  assert_eq(
    empty_table.to_dbc(),
    Err(@moondbc.DbcWriteEmptyValueTable(905U, "State")),
  )
}
