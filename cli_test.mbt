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
