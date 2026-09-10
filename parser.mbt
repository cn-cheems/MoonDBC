///|
fn words(text : StringView) -> Array[StringView] {
  let result : Array[StringView] = []
  for part in text.split(" ") {
    let word = part.trim(chars=" \t")
    if !word.is_empty() {
      result.push(word)
    }
  }
  result
}

///|
fn parse_int(text : StringView) -> Int? {
  Some(@strconv.parse_int(text)) catch {
    _ => None
  }
}

///|
fn parse_uint(text : StringView) -> UInt? {
  Some(@strconv.parse_uint(text)) catch {
    _ => None
  }
}

///|
fn parse_double(text : StringView) -> Double? {
  Some(@strconv.parse_double(text)) catch {
    _ => None
  }
}

///|
fn find_after(text : StringView, start : Int, needle : StringView) -> Int? {
  if start < 0 || start > text.length() {
    return None
  }
  match text[start:].find(needle) {
    Some(offset) => Some(start + offset)
    None => None
  }
}

///|
fn parse_message_line(line : StringView) -> Result[Message, String] {
  let body = line[3:].trim()
  let colon = match body.find(":") {
    Some(value) => value
    None => return Err("message declaration is missing ':'")
  }
  let header = words(body[:colon])
  if header.length() != 2 {
    return Err("message declaration requires an id and name")
  }
  let id = match parse_uint(header[0]) {
    Some(value) => value
    None => return Err("message id is not an unsigned integer")
  }
  let tail = words(body[colon + 1:])
  if tail.length() < 2 {
    return Err("message declaration requires payload size and transmitter")
  }
  let payload_size = match parse_int(tail[0]) {
    Some(value) => value
    None => return Err("message payload size is not an integer")
  }
  if payload_size < 0 || payload_size > 64 {
    return Err("message payload size must be between 0 and 64 bytes")
  }
  Ok({
    id,
    name: header[1].to_owned(),
    payload_size,
    transmitter: tail[1].to_owned(),
    signals: [],
  })
}

///|
fn parse_multiplex(text : StringView) -> MultiplexRole? {
  if text == "M" {
    return Some(Multiplexer)
  }
  if text.has_prefix("m") {
    let value_text = if text.has_suffix("M") {
      text[1:text.length() - 1]
    } else {
      text[1:]
    }
    return match parse_int(value_text) {
      Some(value) if value >= 0 => Some(Multiplexed(value))
      _ => None
    }
  }
  None
}

///|
fn parse_signal_line(line : StringView) -> Result[Signal, String] {
  let body = line[3:].trim()
  let colon = match body.find(":") {
    Some(value) => value
    None => return Err("signal declaration is missing ':'")
  }
  let header = words(body[:colon])
  if header.length() < 1 || header.length() > 2 {
    return Err("signal declaration has an invalid name or multiplex marker")
  }
  let multiplex = if header.length() == 2 {
    match parse_multiplex(header[1]) {
      Some(value) => value
      None => return Err("signal multiplex marker is invalid")
    }
  } else {
    Plain
  }
  let layout = body[colon + 1:].trim()
  let pipe = match layout.find("|") {
    Some(value) => value
    None => return Err("signal layout is missing '|'")
  }
  let at = match find_after(layout, pipe + 1, "@") {
    Some(value) => value
    None => return Err("signal layout is missing '@'")
  }
  if at + 3 > layout.length() {
    return Err("signal layout is missing byte order or signedness")
  }
  let start_bit = match parse_int(layout[:pipe].trim()) {
    Some(value) => value
    None => return Err("signal start bit is not an integer")
  }
  let bit_length = match parse_int(layout[pipe + 1:at].trim()) {
    Some(value) => value
    None => return Err("signal bit length is not an integer")
  }
  if start_bit < 0 {
    return Err("signal start bit must not be negative")
  }
  if bit_length < 1 || bit_length > 64 {
    return Err("signal bit length must be between 1 and 64")
  }
  let byte_order = match layout[at + 1:at + 2] {
    "0" => Motorola
    "1" => Intel
    _ => return Err("signal byte order must be 0 or 1")
  }
  let value_kind = match layout[at + 2:at + 3] {
    "+" => Unsigned
    "-" => Signed
    _ => return Err("signal signedness must be '+' or '-'")
  }
  let open_paren = match find_after(layout, at + 3, "(") {
    Some(value) => value
    None => return Err("signal scale is missing '('")
  }
  let comma = match find_after(layout, open_paren + 1, ",") {
    Some(value) => value
    None => return Err("signal scale is missing ','")
  }
  let close_paren = match find_after(layout, comma + 1, ")") {
    Some(value) => value
    None => return Err("signal scale is missing ')'")
  }
  let factor = match parse_double(layout[open_paren + 1:comma].trim()) {
    Some(value) => value
    None => return Err("signal factor is not a number")
  }
  let offset = match parse_double(layout[comma + 1:close_paren].trim()) {
    Some(value) => value
    None => return Err("signal offset is not a number")
  }
  let open_range = match find_after(layout, close_paren + 1, "[") {
    Some(value) => value
    None => return Err("signal range is missing '['")
  }
  let range_pipe = match find_after(layout, open_range + 1, "|") {
    Some(value) => value
    None => return Err("signal range is missing '|'")
  }
  let close_range = match find_after(layout, range_pipe + 1, "]") {
    Some(value) => value
    None => return Err("signal range is missing ']'")
  }
  let minimum = match parse_double(layout[open_range + 1:range_pipe].trim()) {
    Some(value) => value
    None => return Err("signal minimum is not a number")
  }
  let maximum = match parse_double(layout[range_pipe + 1:close_range].trim()) {
    Some(value) => value
    None => return Err("signal maximum is not a number")
  }
  if minimum > maximum {
    return Err("signal minimum must not exceed maximum")
  }
  let open_quote = match find_after(layout, close_range + 1, "\"") {
    Some(value) => value
    None => return Err("signal unit is missing an opening quote")
  }
  let close_quote = match find_after(layout, open_quote + 1, "\"") {
    Some(value) => value
    None => return Err("signal unit is missing a closing quote")
  }
  let receivers : Array[String] = []
  let receiver_text = layout[close_quote + 1:].trim()
  if !receiver_text.is_empty() {
    for receiver in receiver_text.split(",") {
      let name = receiver.trim()
      if !name.is_empty() {
        receivers.push(name.to_owned())
      }
    }
  }
  Ok({
    name: header[0].to_owned(),
    start_bit,
    bit_length,
    byte_order,
    value_kind,
    factor,
    offset,
    minimum,
    maximum,
    unit: layout[open_quote + 1:close_quote].to_owned(),
    receivers,
    multiplex,
  })
}

///|
fn parse_version_line(line : StringView) -> String? {
  match line.find("\"") {
    None => None
    Some(first_quote) =>
      match find_after(line, first_quote + 1, "\"") {
        None => None
        Some(second_quote) =>
          Some(line[first_quote + 1:second_quote].to_owned())
      }
  }
}

///|
fn contains_message_id(messages : Array[Message], id : UInt) -> Bool {
  for message in messages {
    if message.id == id {
      return true
    }
  }
  false
}

///|
fn contains_signal_name(message : Message, name : StringView) -> Bool {
  for signal in message.signals {
    if signal.name.view() == name {
      return true
    }
  }
  false
}

///|
fn contains_node(nodes : Array[String], name : StringView) -> Bool {
  for node in nodes {
    if node.view() == name {
      return true
    }
  }
  false
}

///|
fn add_diagnostic(
  diagnostics : Array[Diagnostic],
  line : Int,
  code : String,
  message : String,
) -> Unit {
  diagnostics.push({ line, column: 1, code, message, })
}

///|
/// Parse the core declarations of a DBC document while retaining all recoverable
/// errors as source-line diagnostics.
pub fn parse(source : StringView) -> ParseResult {
  let messages : Array[Message] = []
  let nodes : Array[String] = []
  let diagnostics : Array[Diagnostic] = []
  let mut version : String? = None
  let mut current_message : Int? = None
  let mut line_number = 0
  for raw_line in source.split("\n") {
    line_number += 1
    let line = raw_line.trim(chars=" \t\r")
    if line.is_empty() {
      continue
    }
    if line.has_prefix("VERSION") {
      match parse_version_line(line) {
        Some(value) => version = Some(value)
        None =>
          add_diagnostic(
            diagnostics, line_number, "DBC001", "invalid VERSION declaration",
          )
      }
    } else if line.has_prefix("BU_:") {
      for node in words(line[4:]) {
        if !contains_node(nodes, node) {
          nodes.push(node.to_owned())
        }
      }
    } else if line.has_prefix("BO_ ") {
      match parse_message_line(line) {
        Ok(message) =>
          if contains_message_id(messages, message.id) {
            add_diagnostic(
              diagnostics,
              line_number,
              "DBC003",
              "duplicate message id \{message.id}",
            )
            current_message = None
          } else {
            messages.push(message)
            current_message = Some(messages.length() - 1)
          }
        Err(message) => {
          add_diagnostic(diagnostics, line_number, "DBC002", message)
          current_message = None
        }
      }
    } else if line.has_prefix("SG_ ") {
      match current_message {
        None =>
          add_diagnostic(
            diagnostics, line_number, "DBC004", "signal declaration appears before a valid message",
          )
        Some(message_index) =>
          match parse_signal_line(line) {
            Ok(signal) => {
              let message = messages[message_index]
              if contains_signal_name(message, signal.name) {
                add_diagnostic(
                  diagnostics,
                  line_number,
                  "DBC006",
                  "duplicate signal name \{signal.name}",
                )
              } else {
                message.signals.push(signal)
              }
            }
            Err(message) =>
              add_diagnostic(diagnostics, line_number, "DBC005", message)
          }
      }
    }
  }
  { database: { version, nodes, messages, }, diagnostics, }
}
