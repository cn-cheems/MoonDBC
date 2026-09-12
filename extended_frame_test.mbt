///|
test "parse and preserve bit-31 DBC extended identifiers" {
  let source =
    #|VAL_ 2147483939 State 0 "Off" 1 "On";
    #|CM_ BO_ 2147483939 "Extended status";
    #|BO_TX_BU_ 2147483939 : ECU,Backup;
    #|BU_: ECU Backup
    #|BO_ 291 StandardStatus: 1 ECU
    #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
    #|BO_ 2147483939 ExtendedStatus: 1 ECU
    #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
  let parsed = @moondbc.parse(source)
  assert_eq(parsed.diagnostics, [])
  let standard = parsed.database.messages[0]
  let extended = parsed.database.messages[1]
  assert_eq(standard.frame_id(), 0x123U)
  assert_eq(standard.is_extended_frame(), false)
  assert_eq(extended.id, 2147483939U)
  assert_eq(extended.frame_id(), 0x123U)
  assert_eq(extended.is_extended_frame(), true)
  assert_eq(
    parsed.database.find_can_message(0x123U, false).unwrap().name,
    "StandardStatus",
  )
  assert_eq(
    parsed.database.find_can_message(0x123U, true).unwrap().name,
    "ExtendedStatus",
  )
  assert_eq(
    parsed.database.can_message_comment(0x123U, true),
    Some("Extended status"),
  )
  assert_eq(
    parsed.database.can_value_label(0x123U, true, "State", 1L),
    Some("On"),
  )
  assert_eq(extended.additional_transmitters, ["Backup"])
  let reparsed = @moondbc.parse(parsed.database.to_dbc().unwrap())
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, parsed.database)
}

///|
test "distinguish standard and extended SocketCAN frames with equal ids" {
  let database = @moondbc.parse(
      (
        #|BO_ 291 StandardStatus: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
        #|BO_ 2147483939 ExtendedStatus: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
      ),
    ).database
  let standard = @moondbc.parse_can_frame("123#01").unwrap()
  let extended = @moondbc.parse_can_frame("00000123#02").unwrap()
  assert_eq(standard.id, extended.id)
  assert_eq(standard.is_extended_frame, false)
  assert_eq(extended.is_extended_frame, true)
  assert_eq(standard.to_text(), Ok("123#01"))
  assert_eq(extended.to_text(), Ok("00000123#02"))
  let standard_decoded = database.decode_can_frame(standard).unwrap()
  let extended_decoded = database.decode_can_frame(extended).unwrap()
  assert_eq(standard_decoded.name, "StandardStatus")
  assert_eq(standard_decoded.is_extended_frame, false)
  assert_eq(extended_decoded.name, "ExtendedStatus")
  assert_eq(extended_decoded.is_extended_frame, true)
  assert_eq(extended_decoded.signals[0].physical, 2.0)
}

///|
test "encode a complete extended CAN frame" {
  let database = @moondbc.parse(
      (
        #|BO_ 2147483939 ExtendedStatus: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
      ),
    ).database
  let frame = database
    .encode_can_frame(0x123U, true, [{ name: "State", physical: 7.0, }])
    .unwrap()
  assert_eq(frame.to_text(), Ok("00000123#07"))
  assert_eq(database.decode_can_frame(frame).unwrap().name, "ExtendedStatus")
  assert_eq(
    database.encode_can_frame(0x123U, false, [{ name: "State", physical: 7.0, }]),
    Err(@moondbc.FrameEncodeUnknownCanMessage(0x123U, false)),
  )
}

///|
test "reject invalid DBC and CAN identifier ranges" {
  let parsed = @moondbc.parse(
    (
      #|BO_ 2048 InvalidStandard: 1 ECU
      #|BO_ 2684354560 InvalidExtended: 1 ECU
    ),
  )
  assert_eq(parsed.diagnostics.length(), 2)
  assert_eq(parsed.diagnostics[0].code, "DBC002")
  assert_eq(parsed.diagnostics[1].code, "DBC002")
  let message : @moondbc.Message = {
    id: 2048U,
    name: "Invalid",
    payload_size: 1,
    transmitter: "ECU",
    additional_transmitters: [],
    signals: [],
  }
  let database : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [message],
    value_tables: [],
    comments: [],
  }
  assert_eq(database.validate(), [@moondbc.InvalidMessageIdentifierIssue(2048U)])
  assert_eq(
    database.to_dbc(),
    Err(@moondbc.DbcWriteInvalidMessageIdentifier(2048U)),
  )
  assert_eq(
    database.decode_can_payload(0x800U, false, b""),
    Err(@moondbc.InvalidCanFrameIdentifier(0x800U, false)),
  )
  assert_eq(
    database.encode_can_frame(0x20000000U, true, []),
    Err(@moondbc.FrameEncodeInvalidCanIdentifier(0x20000000U, true)),
  )
}

///|
test "generate bus identifiers and extended-frame metadata" {
  let database = @moondbc.parse(
      (
        #|BO_ 2147483939 ExtendedStatus: 1 ECU
      ),
    ).database
  assert_eq(
    database.generate_moonbit_constants(),
    (
      #|// MoonDBC static CAN metadata.
      #|
      #|/// Message ExtendedStatus (extended 291; DBC id 2147483939).
      #|pub const DBC_EXTENDEDSTATUS_2147483939_ID : UInt = 291U
      #|pub const DBC_EXTENDEDSTATUS_2147483939_IS_EXTENDED_FRAME : Bool = true
      #|pub const DBC_EXTENDEDSTATUS_2147483939_PAYLOAD_SIZE : Int = 1
    ),
  )
}
