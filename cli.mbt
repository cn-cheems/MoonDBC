///|
pub(all) enum CliMode {
  CliCheck
  CliList
} derive(Eq, Debug)

///|
pub(all) struct CliOutput {
  stdout : String
  stderr : String
  exit_code : Int
} derive(Eq, Debug)

///|
fn cli_dbc_id_text(id : UInt) -> String {
  match dbc_message_id_parts(id) {
    Some((frame_id, extended)) => {
      let chars : Array[Char] = []
      append_padded_identifier(chars, frame_id, extended)
      if extended {
        "\{String::from_array(chars)} extended"
      } else {
        "\{String::from_array(chars)} standard"
      }
    }
    None => id.to_string()
  }
}

///|
fn cli_signal_count(database : Database) -> Int {
  let mut count = 0
  for message in database.messages {
    count += message.signals.length()
  }
  count
}

///|
fn cli_diagnostics(path : String, diagnostics : Array[Diagnostic]) -> String {
  let lines : Array[String] = []
  for diagnostic in diagnostics {
    lines.push(
      "\{path}:\{diagnostic.line}:\{diagnostic.column} [\{diagnostic.code}] \{diagnostic.message}",
    )
  }
  "\{lines.join("\n")}\n"
}

///|
fn cli_validation_issue(issue : ValidationIssue) -> String {
  match issue {
    InvalidMessageIdentifierIssue(id) =>
      "message \{id} has an invalid DBC identifier"
    DuplicateMessageIdIssue(id) =>
      "message \{cli_dbc_id_text(id)} is declared more than once"
    InvalidPayloadSizeIssue(id, size) =>
      "message \{cli_dbc_id_text(id)} has invalid payload size \{size}"
    DuplicateSignalNameIssue(id, signal) =>
      "message \{cli_dbc_id_text(id)} repeats signal \{signal}"
    InvalidSignalLayoutIssue(id, signal, start, length) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has invalid layout \{start}|\{length}"
    SignalOutsidePayloadIssue(id, signal) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} exceeds its payload"
    InvalidScaleIssue(id, signal, factor, offset) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has invalid scale (\{factor},\{offset})"
    InvalidPhysicalRangeIssue(id, signal, minimum, maximum) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has invalid range [\{minimum}|\{maximum}]"
    MultipleMultiplexersIssue(id) =>
      "message \{cli_dbc_id_text(id)} has multiple multiplexers"
    MissingMultiplexerIssue(id, signal) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has no multiplexer"
    MultiplexSelectorOutOfRangeIssue(id, signal, selector) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has out-of-range selector \{selector}"
    OverlappingSignalsIssue(id, left, right) =>
      "signals \{left} and \{right} overlap in message \{cli_dbc_id_text(id)}"
    DuplicateCommentIssue(_) => "a DBC target has more than one comment"
    UnknownCommentNodeIssue(node) => "comment refers to unknown node \{node}"
    UnknownCommentMessageIssue(id) =>
      "comment refers to unknown message \{cli_dbc_id_text(id)}"
    UnknownCommentSignalIssue(id, signal) =>
      "comment refers to unknown signal \{signal} in message \{cli_dbc_id_text(id)}"
    DuplicateMessageTransmitterIssue(id, transmitter) =>
      "message \{cli_dbc_id_text(id)} repeats transmitter \{transmitter}"
  }
}

///|
fn cli_validation_issues(
  path : String,
  issues : Array[ValidationIssue],
) -> String {
  let lines : Array[String] = []
  for issue in issues {
    lines.push("\{path}: \{cli_validation_issue(issue)}")
  }
  "\{lines.join("\n")}\n"
}

///|
fn cli_can_frame_id_text(id : UInt, extended : Bool) -> String {
  let chars : Array[Char] = []
  append_padded_identifier(chars, id, extended)
  String::from_array(chars)
}

///|
fn cli_frame_text_error(error : CanFrameTextError) -> String {
  match error {
    CanFrameMissingSeparator => "CAN frame is missing '#'"
    CanFrameEmptyIdentifier => "CAN frame identifier is empty"
    CanFrameIdentifierTooLong(length) =>
      "CAN frame identifier has \{length} hexadecimal digits"
    CanFrameInvalidIdentifier(index, _) =>
      "CAN frame identifier has an invalid character at offset \{index}"
    CanFrameIdentifierOutOfRange(id) =>
      "CAN frame identifier \{id} is out of range"
    CanFrameOddPayloadLength(length) =>
      "CAN payload has an odd hexadecimal length of \{length}"
    CanFramePayloadTooLong(length) =>
      "CAN payload has \{length} bytes; at most 64 are supported"
    CanFrameInvalidPayload(index, _) =>
      "CAN payload has an invalid character at offset \{index}"
  }
}

///|
fn cli_can_log_text_error(error : CanLogTextError) -> String {
  match error {
    CanLogInvalidFieldCount(count) =>
      "CAN log record has \{count} fields; expected 1, 2, or 3"
    CanLogInvalidTimestamp(timestamp) =>
      "CAN log record has invalid timestamp \{timestamp}"
    CanLogInvalidInterface(interface_name) =>
      "CAN log record has invalid interface \{interface_name}"
    CanLogMissingFdFlags => "CAN FD record is missing its flags digit"
    CanLogInvalidFdFlags(flags) => "CAN FD record has invalid flags \{flags}"
    CanLogFdFlagsOutOfRange(flags) => "CAN FD flags \{flags} are out of range"
    CanLogTimestampWithoutInterface =>
      "CAN log timestamp requires an interface name"
    CanLogFrameTextError(error) => cli_frame_text_error(error)
  }
}

///|
fn cli_decode_error(error : DecodeError) -> String {
  match error {
    InvalidSignalLayout(start, length) =>
      "invalid signal layout \{start}|\{length}"
    FrameTooShort(required, available) =>
      "signal requires \{required} bits but the frame has \{available}"
  }
}

///|
fn cli_frame_decode_error(error : FrameDecodeError) -> String {
  match error {
    UnknownMessage(id) => "unknown DBC message \{id}"
    InvalidCanFrameIdentifier(id, extended) =>
      "invalid \{if extended { "extended" } else { "standard" }} CAN identifier \{id}"
    UnknownCanMessage(id, extended) =>
      "unknown \{if extended { "extended" } else { "standard" }} CAN message \{cli_can_frame_id_text(id, extended)}"
    PayloadTooShort(required, actual) =>
      "message requires \{required} payload bytes but the frame has \{actual}"
    MissingMultiplexer => "message has multiplexed signals but no multiplexer"
    MultipleMultiplexers => "message has more than one multiplexer"
    SignalDecodeFailed(signal, error) =>
      "signal \{signal} could not be decoded: \{cli_decode_error(error)}"
  }
}

///|
fn cli_trace_error(error : TraceError) -> String {
  match error {
    TraceFrameTextError(error) => cli_frame_text_error(error)
    TraceCanLogTextError(error) => cli_can_log_text_error(error)
    TraceFrameDecodeError(error) => cli_frame_decode_error(error)
  }
}

///|
fn cli_trace_diagnostics(
  path : String,
  diagnostics : Array[TraceDiagnostic],
) -> String {
  let lines : Array[String] = []
  for diagnostic in diagnostics {
    lines.push(
      "\{path}:\{diagnostic.line}: \{cli_trace_error(diagnostic.error)}",
    )
  }
  if lines.is_empty() {
    ""
  } else {
    "\{lines.join("\n")}\n"
  }
}

///|
fn cli_check(path : String, database : Database) -> CliOutput {
  let issues = database.validate()
  if !issues.is_empty() {
    return {
      stdout: "",
      stderr: cli_validation_issues(path, issues),
      exit_code: 1,
    }
  }
  {
    stdout: [
      "OK \{path}",
      "Messages: \{database.messages.length()}",
      "Signals: \{cli_signal_count(database)}",
      "Nodes: \{database.nodes.length()}",
      "",
    ].join("\n"),
    stderr: "",
    exit_code: 0,
  }
}

///|
fn cli_byte_order(order : ByteOrder) -> String {
  match order {
    Intel => "intel"
    Motorola => "motorola"
  }
}

///|
fn cli_value_kind(kind : ValueKind) -> String {
  match kind {
    Unsigned => "unsigned"
    Signed => "signed"
  }
}

///|
fn cli_multiplex(role : MultiplexRole) -> String {
  match role {
    Plain => "plain"
    Multiplexer => "multiplexer"
    Multiplexed(value) => "multiplexed(\{value})"
  }
}

///|
fn cli_list(database : Database) -> String {
  let lines = ["Messages: \{database.messages.length()}"]
  for message in database.messages {
    let bytes = if message.payload_size == 1 { "byte" } else { "bytes" }
    lines.push(
      "\{cli_dbc_id_text(message.id)} \{message.name}, \{message.payload_size} \{bytes}, transmitters: \{message.transmitters().join(",")}",
    )
    for signal in message.signals {
      let unit = if signal.unit.is_empty() { "-" } else { signal.unit }
      lines.push(
        "  \{signal.name}: \{signal.start_bit}|\{signal.bit_length}, \{cli_byte_order(signal.byte_order)}, \{cli_value_kind(signal.value_kind)}, factor=\{signal.factor}, offset=\{signal.offset}, unit=\{unit}, \{cli_multiplex(signal.multiplex)}",
      )
    }
  }
  "\{lines.join("\n")}\n"
}

///|
/// Run a deterministic CLI operation against already-loaded DBC text. Keeping
/// file access outside this function makes command behavior portable and easy
/// to test independently from the native executable.
pub fn run_cli(mode : CliMode, path : String, source : StringView) -> CliOutput {
  let parsed = parse(source)
  if !parsed.diagnostics.is_empty() {
    return {
      stdout: "",
      stderr: cli_diagnostics(path, parsed.diagnostics),
      exit_code: 1,
    }
  }
  match mode {
    CliCheck => cli_check(path, parsed.database)
    CliList => {
      let issues = parsed.database.validate()
      {
        stdout: cli_list(parsed.database),
        stderr: if issues.is_empty() {
          ""
        } else {
          cli_validation_issues(path, issues)
        },
        exit_code: if issues.is_empty() {
          0
        } else {
          1
        },
      }
    }
  }
}

///|
/// Parse and validate a DBC database, decode a SocketCAN or candump trace, and
/// return decoded signal rows as CSV. Valid records are retained when another
/// trace line is malformed; diagnostics and a non-zero exit code report the
/// partial failure.
pub fn run_decode_cli(
  dbc_path : String,
  dbc_source : StringView,
  trace_path : String,
  trace_source : StringView,
) -> CliOutput {
  let parsed = parse(dbc_source)
  if !parsed.diagnostics.is_empty() {
    return {
      stdout: "",
      stderr: cli_diagnostics(dbc_path, parsed.diagnostics),
      exit_code: 1,
    }
  }
  let issues = parsed.database.validate()
  if !issues.is_empty() {
    return {
      stdout: "",
      stderr: cli_validation_issues(dbc_path, issues),
      exit_code: 1,
    }
  }
  let decoded = parsed.database.decode_trace(trace_source)
  let csv = match decoded.to_csv() {
    Ok(value) => value
    Err(error) =>
      return {
        stdout: "",
        stderr: "\{trace_path}: unable to render CSV: \{cli_can_log_text_error(error)}\n",
        exit_code: 1,
      }
  }
  {
    stdout: "\{csv}\r\n",
    stderr: cli_trace_diagnostics(trace_path, decoded.diagnostics),
    exit_code: if decoded.diagnostics.is_empty() {
      0
    } else {
      1
    },
  }
}

///|
/// Parse and validate two DBC sources, then render their compatibility report
/// as Markdown. Breaking changes use exit code 3 so CI can distinguish an
/// incompatible database revision from malformed input.
pub fn run_diff_cli(
  before_path : String,
  before_source : StringView,
  after_path : String,
  after_source : StringView,
) -> CliOutput {
  let before = parse(before_source)
  if !before.diagnostics.is_empty() {
    return {
      stdout: "",
      stderr: cli_diagnostics(before_path, before.diagnostics),
      exit_code: 1,
    }
  }
  let before_issues = before.database.validate()
  if !before_issues.is_empty() {
    return {
      stdout: "",
      stderr: cli_validation_issues(before_path, before_issues),
      exit_code: 1,
    }
  }
  let after = parse(after_source)
  if !after.diagnostics.is_empty() {
    return {
      stdout: "",
      stderr: cli_diagnostics(after_path, after.diagnostics),
      exit_code: 1,
    }
  }
  let after_issues = after.database.validate()
  if !after_issues.is_empty() {
    return {
      stdout: "",
      stderr: cli_validation_issues(after_path, after_issues),
      exit_code: 1,
    }
  }
  let report = before.database.compatibility_report(after.database)
  {
    stdout: "\{report.to_markdown()}\n",
    stderr: if report.breaking_count == 0 {
      ""
    } else {
      "\{after_path}: \{report.breaking_count} breaking change(s) compared with \{before_path}\n"
    },
    exit_code: if report.breaking_count == 0 {
      0
    } else {
      3
    },
  }
}

///|
/// Parse and validate a DBC source, then generate standalone MoonBit constants
/// for build-time integration.
pub fn run_generate_cli(path : String, source : StringView) -> CliOutput {
  let parsed = parse(source)
  if !parsed.diagnostics.is_empty() {
    return {
      stdout: "",
      stderr: cli_diagnostics(path, parsed.diagnostics),
      exit_code: 1,
    }
  }
  let issues = parsed.database.validate()
  if !issues.is_empty() {
    return {
      stdout: "",
      stderr: cli_validation_issues(path, issues),
      exit_code: 1,
    }
  }
  {
    stdout: "\{parsed.database.generate_moonbit_constants()}\n",
    stderr: "",
    exit_code: 0,
  }
}
