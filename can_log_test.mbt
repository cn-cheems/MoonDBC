///|
test "parse compact and interface-prefixed CAN log records" {
  let compact = @moondbc.parse_can_log_record("123#0aff").unwrap()
  assert_eq(compact.timestamp, None)
  assert_eq(compact.interface_name, None)
  assert_eq(compact.fd_flags, None)
  assert_eq(compact.frame, {
    id: 0x123U,
    is_extended_frame: false,
    payload: b"\x0a\xff",
  })
  assert_eq(compact.to_text(), Ok("123#0AFF"))
  let prefixed = @moondbc.parse_can_log_record("vcan0 123#01").unwrap()
  assert_eq(prefixed.timestamp, None)
  assert_eq(prefixed.interface_name, Some("vcan0"))
  assert_eq(prefixed.fd_flags, None)
  assert_eq(prefixed.to_text(), Ok("vcan0 123#01"))
}

///|
test "parse and format SocketCAN FD records" {
  let zero_flags = @moondbc.parse_can_log_record("123##0").unwrap()
  assert_eq(zero_flags.fd_flags, Some(0))
  assert_eq(zero_flags.to_text(), Ok("123##0"))
  let record = @moondbc.parse_can_log_record(
    "(1697042645.123456) can0 123##1DEADBEEF",
  ).unwrap()
  assert_eq(record.timestamp, Some("1697042645.123456"))
  assert_eq(record.interface_name, Some("can0"))
  assert_eq(record.fd_flags, Some(1))
  assert_eq(record.frame, {
    id: 0x123U,
    is_extended_frame: false,
    payload: b"\xde\xad\xbe\xef",
  })
  assert_eq(record.to_text(), Ok("(1697042645.123456) can0 123##1DEADBEEF"))
  let maximum : @moondbc.CanLogRecord = {
    timestamp: None,
    interface_name: None,
    fd_flags: Some(4),
    frame: {
      id: 0x123U,
      is_extended_frame: false,
      payload: Bytes::make(64, b'\xaa'),
    },
  }
  let encoded = maximum.to_text().unwrap()
  assert_eq(@moondbc.parse_can_log_record(encoded).unwrap(), maximum)
}

///|
test "parse timestamped candump records and flexible whitespace" {
  let record = @moondbc.parse_can_log_record(
    "\t(1697042645.123456)   can0\t1fffffff#deadbeef ",
  ).unwrap()
  assert_eq(record.timestamp, Some("1697042645.123456"))
  assert_eq(record.interface_name, Some("can0"))
  assert_eq(record.fd_flags, None)
  assert_eq(record.frame.id, 0x1FFFFFFFU)
  assert_eq(record.frame.is_extended_frame, true)
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
  assert_eq(
    @moondbc.parse_can_log_record("123##"),
    Err(@moondbc.CanLogMissingFdFlags),
  )
  assert_eq(
    @moondbc.parse_can_log_record("123##Z00"),
    Err(@moondbc.CanLogInvalidFdFlags("Z")),
  )
}

///|
test "validate metadata when formatting CAN log records" {
  let frame : @moondbc.CanFrame = {
    id: 1U,
    is_extended_frame: false,
    payload: b"",
  }
  let missing_interface : @moondbc.CanLogRecord = {
    timestamp: Some("1.25"),
    interface_name: None,
    fd_flags: None,
    frame,
  }
  assert_eq(
    missing_interface.to_text(),
    Err(@moondbc.CanLogTimestampWithoutInterface),
  )
  let invalid_timestamp : @moondbc.CanLogRecord = {
    timestamp: Some("NaN"),
    interface_name: Some("can0"),
    fd_flags: None,
    frame,
  }
  assert_eq(
    invalid_timestamp.to_text(),
    Err(@moondbc.CanLogInvalidTimestamp("NaN")),
  )
  let invalid_flags : @moondbc.CanLogRecord = {
    timestamp: None,
    interface_name: None,
    fd_flags: Some(0x10),
    frame,
  }
  assert_eq(invalid_flags.to_text(), Err(@moondbc.CanLogFdFlagsOutOfRange(16)))
}
