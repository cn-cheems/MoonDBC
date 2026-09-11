///|
test "decode valid trace lines and skip comments" {
  let database = @moondbc.parse(
      (
        #|BO_ 291 Status: 2 ECU
        #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" Logger
        #|BO_ 292 Switch: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|1] "" Logger
        #|VAL_ 292 State 0 "Off" 1 "On";
      ),
    ).database
  let trace =
    #|// capture starts here
    #|123#F401
    #|
    #|124#01
  let result = database.decode_trace(trace)
  assert_eq(result.is_valid(), true)
  assert_eq(result.diagnostics, [])
  assert_eq(result.frames.length(), 2)
  assert_eq(result.frames[0].line, 2)
  assert_eq(result.frames[0].timestamp, None)
  assert_eq(result.frames[0].interface_name, None)
  assert_eq(result.frames[0].fd_flags, None)
  assert_eq(result.frames[0].decoded.signals[0].physical, 250.0)
  assert_eq(result.frames[1].line, 4)
  assert_eq(result.frames[1].decoded.signals[0].label, Some("On"))
}

///|
test "retain trace diagnostics and continue decoding" {
  let database = @moondbc.parse(
      (
        #|BO_ 291 Status: 2 ECU
        #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" Logger
      ),
    ).database
  let trace =
    #|missing-separator
    #|(bad-time) can0 123#F401
    #|999#00
    #|123#00
    #|123#F401
  let result = database.decode_trace(trace)
  assert_eq(result.is_valid(), false)
  assert_eq(result.frames.length(), 1)
  assert_eq(result.frames[0].line, 5)
  assert_eq(result.diagnostics, [
    {
      line: 1,
      text: "missing-separator",
      error: @moondbc.TraceFrameTextError(@moondbc.CanFrameMissingSeparator),
    },
    {
      line: 2,
      text: "(bad-time) can0 123#F401",
      error: @moondbc.TraceCanLogTextError(
        @moondbc.CanLogInvalidTimestamp("(bad-time)"),
      ),
    },
    {
      line: 3,
      text: "999#00",
      error: @moondbc.TraceFrameDecodeError(@moondbc.UnknownMessage(0x999U)),
    },
    {
      line: 4,
      text: "123#00",
      error: @moondbc.TraceFrameDecodeError(@moondbc.PayloadTooShort(2, 1)),
    },
  ])
}

///|
test "export decoded trace values as CSV" {
  let database = @moondbc.parse(
      (
        #|BO_ 291 Status: 3 ECU
        #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" Logger
        #| SG_ State : 16|8@1+ (1,0) [0|1] "" Logger
        #|VAL_ 291 State 0 "Off" 1 "On, ready";
      ),
    ).database
  let result = database.decode_trace("(1697042645.5) can0 123##1F40101")
  assert_eq(
    result.to_csv(),
    Ok(
      [
        "line,timestamp,interface,fd_flags,frame,message,signal,raw,physical,unit,label",
        "1,\"1697042645.5\",\"can0\",1,123##1F40101,\"Status\",\"Speed\",500,250,\"km/h\",\"\"",
        "1,\"1697042645.5\",\"can0\",1,123##1F40101,\"Status\",\"State\",1,1,\"\",\"On, ready\"",
      ].join("\r\n"),
    ),
  )
}

///|
test "escape quotes in CSV text fields" {
  let result : @moondbc.TraceDecodeResult = {
    frames: [
      {
        line: 7,
        timestamp: None,
        interface_name: None,
        fd_flags: None,
        frame: { id: 1U, payload: b"\x01", },
        decoded: {
          id: 1U,
          name: "Motor \"A\"",
          signals: [
            {
              name: "State",
              raw: @moondbc.UnsignedRaw(1UL),
              physical: 1.0,
              unit: "",
              label: Some("Ready \"now\""),
            },
          ],
        },
      },
    ],
    diagnostics: [],
  }
  assert_eq(
    result.to_csv(),
    Ok(
      [
        "line,timestamp,interface,fd_flags,frame,message,signal,raw,physical,unit,label",
        "7,\"\",\"\",,001#01,\"Motor \"\"A\"\"\",\"State\",1,1,\"\",\"Ready \"\"now\"\"\"",
      ].join("\r\n"),
    ),
  )
}

///|
test "export an empty trace with a CSV header" {
  let result : @moondbc.TraceDecodeResult = { frames: [], diagnostics: [], }
  assert_eq(
    result.to_csv(),
    Ok(
      "line,timestamp,interface,fd_flags,frame,message,signal,raw,physical,unit,label",
    ),
  )
}

///|
test "report invalid frames during CSV export" {
  let result : @moondbc.TraceDecodeResult = {
    frames: [
      {
        line: 1,
        timestamp: None,
        interface_name: None,
        fd_flags: None,
        frame: { id: 0x20000000U, payload: b"", },
        decoded: { id: 0x20000000U, name: "Invalid", signals: [], },
      },
    ],
    diagnostics: [],
  }
  assert_eq(
    result.to_csv(),
    Err(
      @moondbc.CanLogFrameTextError(
        @moondbc.CanFrameIdentifierOutOfRange(0x20000000U),
      ),
    ),
  )
}
