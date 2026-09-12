///|
test "parse query and round trip multiple message transmitters" {
  let source =
    #|BO_TX_BU_ 100 : ECU,Backup,Gateway;
    #|BU_: ECU Backup Gateway
    #|BO_ 100 Status: 1 ECU
    #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
  let parsed = @moondbc.parse(source)
  assert_eq(parsed.diagnostics, [])
  let message = parsed.database.messages[0]
  assert_eq(message.transmitter, "ECU")
  assert_eq(message.additional_transmitters, ["Backup", "Gateway"])
  assert_eq(message.transmitters(), ["ECU", "Backup", "Gateway"])
  assert_eq(message.is_transmitted_by("Backup"), true)
  assert_eq(message.is_transmitted_by("Logger"), false)
  let written = parsed.database.to_dbc().unwrap()
  assert_eq(
    written,
    (
      #|BU_: ECU Backup Gateway
      #|
      #|BO_ 100 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
      #|
      #|BO_TX_BU_ 100 : ECU,Backup,Gateway;
    ),
  )
  let reparsed = @moondbc.parse(written)
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, parsed.database)
}

///|
test "diagnose invalid unknown and repeated transmitter declarations" {
  let result = @moondbc.parse(
    (
      #|BO_ 100 Status: 1 ECU
      #|BO_TX_BU_ 100 : ECU,ECU;
      #|BO_TX_BU_ 999 : ECU,Backup;
      #|BO_TX_BU_ 100 : ECU,Backup;
      #|BO_TX_BU_ 100 : ECU,Gateway;
    ),
  )
  let codes : Array[String] = []
  for diagnostic in result.diagnostics {
    codes.push(diagnostic.code)
  }
  assert_eq(codes, ["DBC016", "DBC017", "DBC018"])
  assert_eq(result.database.messages[0].additional_transmitters, ["Backup"])
}

///|
test "validate and reject duplicate message transmitters" {
  let message : @moondbc.Message = {
    id: 101U,
    name: "Status",
    payload_size: 1,
    transmitter: "ECU",
    additional_transmitters: ["ECU", "Backup", "Backup"],
    signals: [],
  }
  let database : @moondbc.Database = {
    version: None,
    nodes: ["ECU", "Backup"],
    messages: [message],
    value_tables: [],
    comments: [],
  }
  assert_eq(database.validate(), [
    @moondbc.DuplicateMessageTransmitterIssue(101U, "ECU"),
    @moondbc.DuplicateMessageTransmitterIssue(101U, "Backup"),
  ])
  assert_eq(
    database.to_dbc(),
    Err(@moondbc.DbcWriteDuplicateTransmitter(101U, "ECU")),
  )
}

///|
test "diff reports changed message transmitter metadata" {
  let before = @moondbc.parse(
      (
        #|BO_ 102 Status: 1 ECU
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|BO_ 102 Status: 1 ECU
        #|BO_TX_BU_ 102 : ECU,Backup;
      ),
    ).database
  let changes = before.diff(after)
  assert_eq(changes, [
    @moondbc.MessageMetadataChangedChange(
      102U,
      {
        name: "Status",
        payload_size: 1,
        transmitter: "ECU",
        additional_transmitters: [],
      },
      {
        name: "Status",
        payload_size: 1,
        transmitter: "ECU",
        additional_transmitters: ["Backup"],
      },
    ),
  ])
  assert_eq(
    changes[0].summary(),
    "Message 102 metadata changed from Status/1 bytes/1 transmitter(s) to Status/1 bytes/2 transmitter(s).",
  )
}
