///|
test "parse compact and interface-prefixed CAN log records" {
  let compact = @moondbc.parse_can_log_record("123#0aff").unwrap()
  assert_eq(compact.timestamp, None)
  assert_eq(compact.interface_name, None)
  assert_eq(compact.frame, { id: 0x123U, payload: b"\x0a\xff", })
  assert_eq(compact.to_text(), Ok("123#0AFF"))
  let prefixed = @moondbc.parse_can_log_record("vcan0 123#01").unwrap()
  assert_eq(prefixed.timestamp, None)
  assert_eq(prefixed.interface_name, Some("vcan0"))
  assert_eq(prefixed.to_text(), Ok("vcan0 123#01"))
}

///|
test "parse timestamped candump records and flexible whitespace" {
  let record = @moondbc.parse_can_log_record(
    "\t(1697042645.123456)   can0\t1fffffff#deadbeef ",
  ).unwrap()
  assert_eq(record.timestamp, Some("1697042645.123456"))
  assert_eq(record.interface_name, Some("can0"))
  assert_eq(record.frame.id, 0x1FFFFFFFU)
  assert_eq(record.frame.payload, b"\xde\xad\xbe\xef")
  assert_eq(record.to_text(), Ok("(1697042645.123456) can0 1FFFFFFF#DEADBEEF"))
}

///|
test "reject malformed candump metadata" {
  assert_eq(
    @moondbc.parse_can_log_record(""),
    Err(@moondbc.CanLogInvalidFieldCount(0)),
  )
  assert_eq(
    @moondbc.parse_can_log_record("one two three four"),
    Err(@moondbc.CanLogInvalidFieldCount(4)),
  )
  assert_eq(
    @moondbc.parse_can_log_record("(not-a-time) can0 123#00"),
    Err(@moondbc.CanLogInvalidTimestamp("(not-a-time)")),
  )
  assert_eq(
    @moondbc.parse_can_log_record("bad/interface 123#00"),
    Err(@moondbc.CanLogInvalidInterface("bad/interface")),
  )
  assert_eq(
    @moondbc.parse_can_log_record("(1.25) 123#00"),
    Err(@moondbc.CanLogTimestampWithoutInterface),
  )
  assert_eq(
    @moondbc.parse_can_log_record("can0 invalid"),
    Err(@moondbc.CanLogFrameTextError(@moondbc.CanFrameMissingSeparator)),
  )
}

///|
test "validate metadata when formatting CAN log records" {
  let frame : @moondbc.CanFrame = { id: 1U, payload: b"", }
  let missing_interface : @moondbc.CanLogRecord = {
    timestamp: Some("1.25"),
    interface_name: None,
    frame,
  }
  assert_eq(
    missing_interface.to_text(),
    Err(@moondbc.CanLogTimestampWithoutInterface),
  )
  let invalid_timestamp : @moondbc.CanLogRecord = {
    timestamp: Some("NaN"),
    interface_name: Some("can0"),
    frame,
  }
  assert_eq(
    invalid_timestamp.to_text(),
    Err(@moondbc.CanLogInvalidTimestamp("NaN")),
  )
}
