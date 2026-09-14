///|
test "check a valid DBC from the command line" {
  let output = @moondbc.run_cli(
    @moondbc.CliCheck,
    "vehicle.dbc",
    (
      #|BU_: ECU Dashboard
      #|BO_ 256 Powertrain: 2 ECU
      #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" Dashboard
    ),
  )
  assert_eq(output, {
    stdout: (
      #|OK vehicle.dbc
      #|Messages: 1
      #|Signals: 1
      #|Nodes: 2
      #|
    ),
    stderr: "",
    exit_code: 0,
  })
}

///|
test "report parser diagnostics through the command line" {
  let output = @moondbc.run_cli(
    @moondbc.CliCheck,
    "broken.dbc",
    (
      #|BO_ invalid
      #|SG_ Orphan : 0|8@1+ (1,0) [0|255] "" ECU
    ),
  )
  assert_eq(output.stdout, "")
  assert_eq(output.exit_code, 1)
  assert_eq(
    output.stderr,
    (
      #|broken.dbc:1:1 [DBC002] message declaration is missing ':'
      #|broken.dbc:2:1 [DBC004] signal declaration appears before a valid message
      #|
    ),
  )
}

///|
test "report semantic validation failures through the command line" {
  let output = @moondbc.run_cli(
    @moondbc.CliCheck,
    "overlap.dbc",
    (
      #|BO_ 300 Status: 1 ECU
      #| SG_ First : 0|8@1+ (1,0) [0|255] "" ECU
      #| SG_ Second : 4|4@1+ (1,0) [0|15] "" ECU
    ),
  )
  assert_eq(output.stdout, "")
  assert_eq(output.exit_code, 1)
  assert_eq(
    output.stderr,
    "overlap.dbc: signals First and Second overlap in message 12C standard\n",
  )
}

///|
test "list standard extended and multiplexed messages" {
  let output = @moondbc.run_cli(
    @moondbc.CliList,
    "network.dbc",
    (
      #|BU_: ECU Backup
      #|BO_ 291 StandardStatus: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
      #|BO_ 2147483939 ExtendedStatus: 2 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" ECU
      #| SG_ Voltage m1 : 15|8@0- (0.5,-1) [-1|126.5] "V" ECU
      #|BO_TX_BU_ 2147483939 : ECU,Backup;
    ),
  )
  assert_eq(output.exit_code, 0)
  assert_eq(output.stderr, "")
  assert_eq(
    output.stdout,
    (
      #|Messages: 2
      #|123 standard StandardStatus, 1 byte, transmitters: ECU
      #|  State: 0|8, intel, unsigned, factor=1, offset=0, unit=-, plain
      #|00000123 extended ExtendedStatus, 2 bytes, transmitters: ECU,Backup
      #|  Mode: 0|8, intel, unsigned, factor=1, offset=0, unit=-, multiplexer
      #|  Voltage: 15|8, motorola, signed, factor=0.5, offset=-1, unit=V, multiplexed(1)
      #|
    ),
  )
}

///|
test "decode a candump trace as CSV" {
  let output = @moondbc.run_decode_cli(
    "vehicle.dbc",
    (
      #|BO_ 291 Status: 3 ECU
      #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" Logger
      #| SG_ State : 16|8@1+ (1,0) [0|1] "" Logger
      #|VAL_ 291 State 0 "Off" 1 "On";
    ),
    "capture.log",
    "(1697042645.5) can0 123#F40101",
  )
  assert_eq(output.exit_code, 0)
  assert_eq(output.stderr, "")
  assert_eq(
    output.stdout,
    [
      "line,timestamp,interface,fd_flags,frame,message,signal,raw,physical,unit,label",
      "1,\"1697042645.5\",\"can0\",,123#F40101,\"Status\",\"Speed\",500,250,\"km/h\",\"\"",
      "1,\"1697042645.5\",\"can0\",,123#F40101,\"Status\",\"State\",1,1,\"\",\"On\"",
      "",
    ].join("\r\n"),
  )
}

///|
test "retain valid trace rows when another row is malformed" {
  let output = @moondbc.run_decode_cli(
    "vehicle.dbc",
    (
      #|BO_ 291 Status: 2 ECU
      #| SG_ Speed : 0|16@1+ (0.5,0) [0|32767.5] "km/h" Logger
    ),
    "capture.log",
    (
      #|missing-separator
      #|123#F401
    ),
  )
  assert_eq(output.exit_code, 1)
  assert_eq(output.stderr, "capture.log:1: CAN frame is missing '#'\n")
  assert_eq(
    output.stdout,
    [
      "line,timestamp,interface,fd_flags,frame,message,signal,raw,physical,unit,label",
      "2,\"\",\"\",,123#F401,\"Status\",\"Speed\",500,250,\"km/h\",\"\"", "",
    ].join("\r\n"),
  )
}

///|
test "reject an invalid DBC before decoding a trace" {
  let output = @moondbc.run_decode_cli(
    "invalid.dbc",
    (
      #|BO_ 300 Status: 1 ECU
      #| SG_ First : 0|8@1+ (1,0) [0|255] "" ECU
      #| SG_ Second : 4|4@1+ (1,0) [0|15] "" ECU
    ),
    "capture.log",
    "12C#00",
  )
  assert_eq(output.stdout, "")
  assert_eq(output.exit_code, 1)
  assert_eq(
    output.stderr,
    "invalid.dbc: signals First and Second overlap in message 12C standard\n",
  )
}

///|
test "accept a backward-compatible DBC revision" {
  let output = @moondbc.run_diff_cli(
    "before.dbc",
    "BO_ 501 Existing: 1 ECU",
    "after.dbc",
    (
      #|BO_ 501 Existing: 1 ECU
      #|BO_ 502 Added: 1 ECU
    ),
  )
  assert_eq(output.exit_code, 0)
  assert_eq(output.stderr, "")
  assert_eq(
    output.stdout,
    [
      "# DBC Compatibility Report", "", "- Breaking changes: 0", "- Non-breaking changes: 1",
      "- Informational changes: 0", "", "## Changes", "", "- **Non-breaking**: Message 502 (Added) was added.",
      "",
    ].join("\n"),
  )
}

///|
test "fail a compatibility gate on breaking changes" {
  let output = @moondbc.run_diff_cli(
    "before.dbc", "BO_ 503 Removed: 1 ECU", "after.dbc", "BO_ 504 Added: 1 ECU",
  )
  assert_eq(output.exit_code, 3)
  assert_eq(
    output.stderr,
    "after.dbc: 1 breaking change(s) compared with before.dbc\n",
  )
  assert_eq(
    output.stdout,
    [
      "# DBC Compatibility Report", "", "- Breaking changes: 1", "- Non-breaking changes: 1",
      "- Informational changes: 0", "", "## Changes", "", "- **Breaking**: Message 503 (Removed) was removed.",
      "- **Non-breaking**: Message 504 (Added) was added.", "",
    ].join("\n"),
  )
}

///|
test "report which DBC revision is malformed" {
  let output = @moondbc.run_diff_cli(
    "before.dbc", "BO_ 501 Existing: 1 ECU", "after.dbc", "BO_ invalid",
  )
  assert_eq(output.stdout, "")
  assert_eq(output.exit_code, 1)
  assert_eq(
    output.stderr,
    "after.dbc:1:1 [DBC002] message declaration is missing ':'\n",
  )
}

///|
test "generate MoonBit constants from a DBC file" {
  let output = @moondbc.run_generate_cli(
    "vehicle.dbc",
    (
      #|BO_ 256 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|1] "" Dashboard
    ),
  )
  assert_eq(output.exit_code, 0)
  assert_eq(output.stderr, "")
  assert_eq(
    output.stdout,
    [
      "// MoonDBC static CAN metadata.", "", "/// Message Status (256).", "pub const DBC_STATUS_256_ID : UInt = 256U",
      "pub const DBC_STATUS_256_IS_EXTENDED_FRAME : Bool = false", "pub const DBC_STATUS_256_PAYLOAD_SIZE : Int = 1",
      "", "/// Signal State in message Status.", "pub const DBC_STATUS_256_STATE_0_START_BIT : Int = 0",
      "pub const DBC_STATUS_256_STATE_0_BIT_LENGTH : Int = 8", "pub const DBC_STATUS_256_STATE_0_IS_INTEL : Bool = true",
      "pub const DBC_STATUS_256_STATE_0_IS_SIGNED : Bool = false", "pub const DBC_STATUS_256_STATE_0_FACTOR : Double = 1",
      "pub const DBC_STATUS_256_STATE_0_OFFSET : Double = 0", "pub const DBC_STATUS_256_STATE_0_MINIMUM : Double = 0",
      "pub const DBC_STATUS_256_STATE_0_MAXIMUM : Double = 1", "",
    ].join("\n"),
  )
}

///|
test "reject invalid DBC input during generation" {
  let output = @moondbc.run_generate_cli(
    "invalid.dbc",
    (
      #|BO_ 300 Status: 1 ECU
      #| SG_ First : 0|8@1+ (1,0) [0|255] "" ECU
      #| SG_ Second : 4|4@1+ (1,0) [0|15] "" ECU
    ),
  )
  assert_eq(output.stdout, "")
  assert_eq(output.exit_code, 1)
  assert_eq(
    output.stderr,
    "invalid.dbc: signals First and Second overlap in message 12C standard\n",
  )
}

///|
test "encode physical values as a SocketCAN frame" {
  let source =
    #|BO_ 256 Powertrain: 8 ECU
    #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
    #| SG_ CoolantTemp : 23|8@0- (1,-40) [-40|215] "degC" Dashboard
    #| SG_ Gear : 32|8@1+ (1,0) [0|7] "" Dashboard
  let output = @moondbc.run_encode_cli("vehicle.dbc", source, "100", [
    "Gear=1", "CoolantTemp=85", "EngineSpeed=1000",
  ])
  assert_eq(output, {
    stdout: "100#401F7D0001000000\n",
    stderr: "",
    exit_code: 0,
  })
  let frame = @moondbc.parse_can_frame(output.stdout).unwrap()
  let decoded = @moondbc.parse(source).database.decode_can_frame(frame).unwrap()
  assert_eq(decoded.signals[0].physical, 1000.0)
  assert_eq(decoded.signals[1].physical, 85.0)
  assert_eq(decoded.signals[2].physical, 1.0)
}

///|
test "encode an extended CAN frame from its bus identifier" {
  let output = @moondbc.run_encode_cli(
    "network.dbc",
    (
      #|BO_ 2147483939 ExtendedStatus: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" Dashboard
    ),
    "00000123",
    ["State=5"],
  )
  assert_eq(output, { stdout: "00000123#05\n", stderr: "", exit_code: 0, })
}

///|
test "reject malformed command-line signal assignments" {
  let output = @moondbc.run_encode_cli(
    "vehicle.dbc",
    (
      #|BO_ 256 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" Dashboard
    ),
    "100",
    ["State"],
  )
  assert_eq(output.stdout, "")
  assert_eq(output.exit_code, 1)
  assert_eq(
    output.stderr,
    "moondbc: invalid assignment 'State'; expected NAME=NUMBER\n",
  )
}

///|
test "identify a signal whose physical value cannot be encoded" {
  let output = @moondbc.run_encode_cli(
    "vehicle.dbc",
    (
      #|BO_ 256 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|10] "" Dashboard
    ),
    "100",
    ["State=11"],
  )
  assert_eq(output.stdout, "")
  assert_eq(output.exit_code, 1)
  assert_eq(
    output.stderr,
    "moondbc: signal State could not be encoded: physical value 11 is outside [0,10]\n",
  )
}
