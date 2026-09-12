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
fn parse_int64(text : StringView) -> Int64? {
  Some(@strconv.parse_int64(text)) catch {
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
priv struct PendingValueTable {
  line : Int
  message_id : UInt
  signal_name : String
  entries : Array[ValueDescription]
}

///|
priv struct PendingDbcComment {
  line : Int
  target : DbcCommentTarget
  text : String
}

///|
priv struct PendingMessageTransmitters {
  line : Int
  message_id : UInt
  transmitters : Array[String]
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
    additional_transmitters: [],
    signals: [],
  })
}

///|
fn parse_message_transmitters_line(
  line : StringView,
) -> Result[(UInt, Array[String]), String] {
  let body = line[9:].trim()
  if !body.has_suffix(";") {
    return Err("message transmitter declaration is missing ';'")
  }
  let content = body[:body.length() - 1].trim()
  let colon = match content.find(":") {
    Some(value) => value
    None => return Err("message transmitter declaration is missing ':'")
  }
  let header = words(content[:colon])
  if header.length() != 1 {
    return Err("message transmitter declaration requires one message id")
  }
  let message_id = match parse_uint(header[0]) {
    Some(value) => value
    None => return Err("message transmitter id is not an unsigned integer")
  }
  let transmitter_text = content[colon + 1:].trim()
  if transmitter_text.is_empty() {
    return Err("message transmitter declaration requires at least one node")
  }
  let transmitters : Array[String] = []
  for part in transmitter_text.split(",") {
    let transmitter = part.trim()
    if transmitter.is_empty() {
      return Err("message transmitter declaration contains an empty node")
    }
    for existing in transmitters {
      if existing.view() == transmitter {
        return Err("message transmitter declaration contains a duplicate node")
      }
    }
    transmitters.push(transmitter.to_owned())
  }
  Ok((message_id, transmitters))
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
fn parse_comment_text(text : StringView) -> Result[String, String] {
  let chars : Array[Char] = []
  let mut escaped = false
  let mut closed = false
  for char in text.iter() {
    if closed {
      return Err("comment has text after its closing quote")
    }
    if escaped {
      if char == '"' || char == '\\' {
        chars.push(char)
      } else {
        chars.push('\\')
        chars.push(char)
      }
      escaped = false
    } else if char == '\\' {
      escaped = true
    } else if char == '"' {
      closed = true
    } else {
      chars.push(char)
    }
  }
  if escaped || !closed {
    Err("comment is missing a closing quote")
  } else {
    Ok(String::from_array(chars))
  }
}

///|
fn parse_comment_line(
  line : StringView,
) -> Result[(DbcCommentTarget, String), String] {
  let body = line[3:].trim()
  if !body.has_suffix(";") {
    return Err("comment declaration is missing ';'")
  }
  let content = body[:body.length() - 1].trim()
  let open_quote = match content.find("\"") {
    Some(value) => value
    None => return Err("comment is missing an opening quote")
  }
  let text = match parse_comment_text(content[open_quote + 1:]) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let header = words(content[:open_quote])
  let target = match header {
    [] => DatabaseComment
    [kind, node] if kind == "BU_" => NodeComment(node.to_owned())
    [kind, message_id] if kind == "BO_" =>
      match parse_uint(message_id) {
        Some(value) => MessageComment(value)
        None => return Err("message comment id is not an unsigned integer")
      }
    [kind, message_id, signal] if kind == "SG_" => {
      let id = match parse_uint(message_id) {
        Some(value) => value
        None =>
          return Err("signal comment message id is not an unsigned integer")
      }
      SignalComment(id, signal.to_owned())
    }
    _ => return Err("comment target must be the database, BU_, BO_, or SG_")
  }
  Ok((target, text))
}

///|
fn contains_value_description(
  entries : Array[ValueDescription],
  value : Int64,
) -> Bool {
  for entry in entries {
    if entry.value == value {
      return true
    }
  }
  false
}

///|
fn parse_value_line(
  line : StringView,
) -> Result[(UInt, String, Array[ValueDescription]), String] {
  let body = line[5:].trim()
  if !body.has_suffix(";") {
    return Err("value table declaration is missing ';'")
  }
  let content = body[:body.length() - 1].trim()
  let fields = words(content)
  if fields.length() < 4 {
    return Err("value table requires a message id, signal name, and entry")
  }
  let message_id = match parse_uint(fields[0]) {
    Some(value) => value
    None => return Err("value table message id is not an unsigned integer")
  }
  let signal_start = match find_after(content, fields[0].length(), fields[1]) {
    Some(value) => value
    None => return Err("value table signal name is missing")
  }
  let signal_name = fields[1].to_owned()
  let mut rest = content[signal_start + fields[1].length():].trim()
  let entries : Array[ValueDescription] = []
  while !rest.is_empty() {
    let open_quote = match rest.find("\"") {
      Some(value) => value
      None => return Err("value description is missing an opening quote")
    }
    let raw_fields = words(rest[:open_quote])
    if raw_fields.length() != 1 {
      return Err("value description requires one integer value")
    }
    let value = match parse_int64(raw_fields[0]) {
      Some(value) => value
      None => return Err("value description key is not an integer")
    }
    if contains_value_description(entries, value) {
      return Err("value table contains a duplicate key")
    }
    let close_quote = match find_after(rest, open_quote + 1, "\"") {
      Some(value) => value
      None => return Err("value description is missing a closing quote")
    }
    entries.push({ value, label: rest[open_quote + 1:close_quote].to_owned(), })
    rest = rest[close_quote + 1:].trim()
  }
  Ok((message_id, signal_name, entries))
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
fn find_message_index(messages : Array[Message], id : UInt) -> Int? {
  for index, message in messages {
    if message.id == id {
      return Some(index)
    }
  }
  None
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
fn contains_value_table(
  tables : Array[ValueTable],
  message_id : UInt,
  signal_name : StringView,
) -> Bool {
  for table in tables {
    if table.message_id == message_id && table.signal_name.view() == signal_name {
      return true
    }
  }
  false
}

///|
fn contains_comment_target(
  comments : Array[DbcComment],
  target : DbcCommentTarget,
) -> Bool {
  for comment in comments {
    if comment.target == target {
      return true
    }
  }
  false
}

///|
fn contains_message_reference(ids : Array[UInt], id : UInt) -> Bool {
  for candidate in ids {
    if candidate == id {
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
  let pending_value_tables : Array[PendingValueTable] = []
  let value_tables : Array[ValueTable] = []
  let pending_comments : Array[PendingDbcComment] = []
  let comments : Array[DbcComment] = []
  let pending_message_transmitters : Array[PendingMessageTransmitters] = []
  let resolved_transmitter_messages : Array[UInt] = []
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
    } else if line.has_prefix("BO_TX_BU_ ") {
      match parse_message_transmitters_line(line) {
        Ok((message_id, transmitters)) =>
          pending_message_transmitters.push({
            line: line_number,
            message_id,
            transmitters,
          })
        Err(message) =>
          add_diagnostic(diagnostics, line_number, "DBC016", message)
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
    } else if line.has_prefix("CM_ ") {
      match parse_comment_line(line) {
        Ok((target, text)) =>
          pending_comments.push({ line: line_number, target, text, })
        Err(message) =>
          add_diagnostic(diagnostics, line_number, "DBC011", message)
      }
    } else if line.has_prefix("VAL_ ") {
      match parse_value_line(line) {
        Ok((message_id, signal_name, entries)) =>
          pending_value_tables.push({
            line: line_number,
            message_id,
            signal_name,
            entries,
          })
        Err(message) =>
          add_diagnostic(diagnostics, line_number, "DBC007", message)
      }
    }
  }
  for pending in pending_value_tables {
    match find_message_index(messages, pending.message_id) {
      None =>
        add_diagnostic(
          diagnostics,
          pending.line,
          "DBC008",
          "value table refers to an unknown message",
        )
      Some(message_index) => {
        let message = messages[message_index]
        if !contains_signal_name(message, pending.signal_name) {
          add_diagnostic(
            diagnostics,
            pending.line,
            "DBC009",
            "value table refers to an unknown signal",
          )
        } else if contains_value_table(
            value_tables,
            pending.message_id,
            pending.signal_name,
          ) {
          add_diagnostic(
            diagnostics,
            pending.line,
            "DBC010",
            "duplicate value table for the same signal",
          )
        } else {
          value_tables.push({
            message_id: pending.message_id,
            signal_name: pending.signal_name,
            entries: pending.entries,
          })
        }
      }
    }
  }
  for pending in pending_comments {
    let target_exists = match pending.target {
      DatabaseComment => true
      NodeComment(name) =>
        if contains_node(nodes, name) {
          true
        } else {
          add_diagnostic(
            diagnostics,
            pending.line,
            "DBC012",
            "comment refers to an unknown node",
          )
          false
        }
      MessageComment(message_id) =>
        if find_message_index(messages, message_id) is Some(_) {
          true
        } else {
          add_diagnostic(
            diagnostics,
            pending.line,
            "DBC013",
            "comment refers to an unknown message",
          )
          false
        }
      SignalComment(message_id, signal_name) =>
        match find_message_index(messages, message_id) {
          None => {
            add_diagnostic(
              diagnostics,
              pending.line,
              "DBC013",
              "comment refers to an unknown message",
            )
            false
          }
          Some(message_index) =>
            if contains_signal_name(messages[message_index], signal_name) {
              true
            } else {
              add_diagnostic(
                diagnostics,
                pending.line,
                "DBC014",
                "comment refers to an unknown signal",
              )
              false
            }
        }
    }
    if target_exists {
      if contains_comment_target(comments, pending.target) {
        add_diagnostic(
          diagnostics,
          pending.line,
          "DBC015",
          "duplicate comment for the same target",
        )
      } else {
        comments.push({ target: pending.target, text: pending.text, })
      }
    }
  }
  for pending in pending_message_transmitters {
    match find_message_index(messages, pending.message_id) {
      None =>
        add_diagnostic(
          diagnostics,
          pending.line,
          "DBC017",
          "message transmitter declaration refers to an unknown message",
        )
      Some(message_index) =>
        if contains_message_reference(
            resolved_transmitter_messages,
            pending.message_id,
          ) {
          add_diagnostic(
            diagnostics,
            pending.line,
            "DBC018",
            "duplicate transmitter declaration for the same message",
          )
        } else {
          let message = messages[message_index]
          for transmitter in pending.transmitters {
            if transmitter != message.transmitter {
              message.additional_transmitters.push(transmitter)
            }
          }
          resolved_transmitter_messages.push(pending.message_id)
        }
    }
  }
  {
    database: { version, nodes, messages, value_tables, comments, },
    diagnostics,
  }
}
