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
fn cli_raw_value(value : RawValue) -> String {
  match value {
    UnsignedRaw(value) => value.to_string()
    SignedRaw(value) => value.to_string()
  }
}

///|
fn cli_encode_error(error : EncodeError) -> String {
  match error {
    EncodeInvalidLayout(start, length) =>
      "invalid signal layout \{start}|\{length}"
    EncodeFrameTooShort(required, available) =>
      "signal requires \{required} bits but the frame has \{available}"
    ValueKindMismatch(expected, actual) =>
      "expected a \{cli_value_kind(expected)} raw value, received \{cli_raw_value(actual)}"
    RawValueOutOfRange(value, length) =>
      "raw value \{cli_raw_value(value)} does not fit in \{length} bits"
    InvalidFactor(factor) => "signal has invalid factor \{factor}"
    NonFinitePhysicalValue(value) => "physical value \{value} is not finite"
    PhysicalValueOutOfRange(value, minimum, maximum) =>
      "physical value \{value} is outside [\{minimum},\{maximum}]"
    PhysicalRawOutOfRange(value, length) =>
      "scaled raw value \{value} does not fit in \{length} bits"
  }
}

///|
fn cli_frame_encode_error(error : FrameEncodeError) -> String {
  match error {
    FrameEncodeUnknownMessage(id) => "unknown DBC message \{id}"
    FrameEncodeInvalidCanIdentifier(id, extended) =>
      "invalid \{if extended { "extended" } else { "standard" }} CAN identifier \{id}"
    FrameEncodeUnknownCanMessage(id, extended) =>
      "unknown \{if extended { "extended" } else { "standard" }} CAN message \{cli_can_frame_id_text(id, extended)}"
    FrameEncodeInvalidPayloadSize(size) =>
      "message has invalid payload size \{size}"
    FrameEncodeUnknownSignal(signal) => "unknown signal \{signal}"
    FrameEncodeDuplicateSignal(signal) =>
      "signal \{signal} is assigned more than once"
    FrameEncodeMissingSignal(signal) => "signal \{signal} is not assigned"
    FrameEncodeInactiveSignal(signal, selector) =>
      "signal \{signal} is inactive for multiplex selector \{selector}"
    FrameEncodeMissingMultiplexer =>
      "message has multiplexed signals but no multiplexer"
    FrameEncodeMultipleMultiplexers => "message has more than one multiplexer"
    FrameSignalEncodeFailed(signal, error) =>
      "signal \{signal} could not be encoded: \{cli_encode_error(error)}"
    FrameMultiplexerDecodeFailed(signal, error) =>
      "multiplexer \{signal} could not be read after encoding: \{cli_decode_error(error)}"
  }
}

///|
fn cli_write_error(error : DbcWriteError) -> String {
  match error {
    DbcWriteInvalidToken(context, text) =>
      "\{context} '\{text}' is not a valid DBC token"
    DbcWriteInvalidQuotedText(context, _) =>
      "\{context} contains text that cannot be quoted in DBC syntax"
    DbcWriteInvalidPayloadSize(id, size) =>
      "message \{cli_dbc_id_text(id)} has invalid payload size \{size}"
    DbcWriteNonFiniteSignalNumber(id, signal, field) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has a non-finite \{field}"
    DbcWriteNegativeMultiplexValue(id, signal, value) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has negative multiplex value \{value}"
    DbcWriteEmptyValueTable(id, signal) =>
      "signal \{signal} in message \{cli_dbc_id_text(id)} has an empty value table"
    DbcWriteDuplicateTransmitter(id, transmitter) =>
      "message \{cli_dbc_id_text(id)} repeats transmitter \{transmitter}"
    DbcWriteInvalidMessageIdentifier(id) =>
      "message \{id} has an invalid DBC identifier"
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

///|
fn cli_format_line_is_supported(line : StringView) -> Bool {
  line.is_empty() ||
  line.has_prefix("VERSION") ||
  line.has_prefix("BU_:") ||
  line.has_prefix("BO_TX_BU_ ") ||
  line.has_prefix("BO_ ") ||
  line.has_prefix("SG_ ") ||
  line.has_prefix("CM_ ") ||
  line.has_prefix("VAL_ ")
}

///|
fn cli_first_unsupported_format_line(source : StringView) -> Int? {
  let mut line_number = 0
  for raw_line in source.split("\n") {
    line_number += 1
    let line = raw_line.trim(chars=" \t\r")
    if !cli_format_line_is_supported(line) {
      return Some(line_number)
    }
  }
  None
}

///|
/// Parse and validate a DBC source, then emit the deterministic representation
/// used by `Database::to_dbc`. Check mode produces no standard output and uses
/// exit code 4 when the input differs from that representation. Unsupported
/// declarations are rejected so formatting never silently removes source data.
pub fn run_format_cli(
  path : String,
  source : StringView,
  check_only : Bool,
) -> CliOutput {
  match cli_first_unsupported_format_line(source) {
    Some(line) =>
      return {
        stdout: "",
        stderr: "\{path}:\{line}:1 [DBC019] unsupported declaration cannot be formatted safely\n",
        exit_code: 1,
      }
    None => ()
  }
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
  let formatted = match parsed.database.to_dbc() {
    Ok(text) => "\{text}\n"
    Err(error) =>
      return {
        stdout: "",
        stderr: "\{path}: unable to format DBC: \{cli_write_error(error)}\n",
        exit_code: 1,
      }
  }
  if check_only {
    if source == formatted {
      { stdout: "", stderr: "", exit_code: 0, }
    } else {
      {
        stdout: "",
        stderr: "\{path}: formatting changes required\n",
        exit_code: 4,
      }
    }
  } else {
    { stdout: formatted, stderr: "", exit_code: 0, }
  }
}

///|
fn cli_parse_assignment(text : String) -> Result[SignalAssignment, String] {
  let (name_text, value_text) = match text.view().split_once("=") {
    Some(parts) => parts
    None => return Err("invalid assignment '\{text}'; expected NAME=NUMBER")
  }
  let name = name_text.trim()
  let value = value_text.trim()
  if name.is_empty() || value.is_empty() {
    return Err("invalid assignment '\{text}'; expected NAME=NUMBER")
  }
  let physical = match parse_double(value) {
    Some(value) => value
    None => return Err("assignment '\{text}' has an invalid number")
  }
  Ok({ name: name.to_owned(), physical, })
}

///|
/// Parse and validate a DBC source, encode named physical values into a CAN
/// frame, and render canonical SocketCAN text. The CAN identifier uses one to
/// three hexadecimal digits for a standard frame and four to eight for an
/// extended frame.
pub fn run_encode_cli(
  path : String,
  source : StringView,
  identifier : String,
  assignment_texts : Array[String],
) -> CliOutput {
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
  let selector = match parse_can_frame("\{identifier}#") {
    Ok(frame) => frame
    Err(error) =>
      return {
        stdout: "",
        stderr: "moondbc: invalid CAN identifier '\{identifier}': \{cli_frame_text_error(error)}\n",
        exit_code: 1,
      }
  }
  let assignments : Array[SignalAssignment] = []
  for text in assignment_texts {
    match cli_parse_assignment(text) {
      Ok(assignment) => assignments.push(assignment)
      Err(message) =>
        return { stdout: "", stderr: "moondbc: \{message}\n", exit_code: 1, }
    }
  }
  let frame = match
    parsed.database.encode_can_frame(
      selector.id,
      selector.is_extended_frame,
      assignments,
    ) {
    Ok(frame) => frame
    Err(error) =>
      return {
        stdout: "",
        stderr: "moondbc: \{cli_frame_encode_error(error)}\n",
        exit_code: 1,
      }
  }
  match frame.to_text() {
    Ok(text) => { stdout: "\{text}\n", stderr: "", exit_code: 0, }
    Err(error) =>
      {
        stdout: "",
        stderr: "moondbc: unable to render CAN frame: \{cli_frame_text_error(error)}\n",
        exit_code: 1,
      }
  }
}
