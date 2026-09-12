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
