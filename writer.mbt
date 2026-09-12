///|
pub(all) enum DbcWriteError {
  DbcWriteInvalidToken(String, String)
  DbcWriteInvalidQuotedText(String, String)
  DbcWriteInvalidPayloadSize(UInt, Int)
  DbcWriteNonFiniteSignalNumber(UInt, String, String)
  DbcWriteNegativeMultiplexValue(UInt, String, Int)
  DbcWriteEmptyValueTable(UInt, String)
  DbcWriteDuplicateTransmitter(UInt, String)
  DbcWriteInvalidMessageIdentifier(UInt)
} derive(Eq, Debug)

///|
fn dbc_token_is_valid(text : StringView) -> Bool {
  if text.is_empty() {
    return false
  }
  for char in text.iter() {
    if char == ' ' ||
      char == '\t' ||
      char == '\r' ||
      char == '\n' ||
      char == ':' ||
      char == ',' ||
      char == ';' ||
      char == '"' {
      return false
    }
  }
  true
}

///|
fn check_dbc_token(
  context : String,
  text : String,
) -> Result[Unit, DbcWriteError] {
  if dbc_token_is_valid(text) {
    Ok(())
  } else {
    Err(DbcWriteInvalidToken(context, text))
  }
}

///|
fn dbc_quoted_text_is_valid(text : StringView) -> Bool {
  for char in text.iter() {
    if char == '"' || char == '\r' || char == '\n' {
      return false
    }
  }
  true
}

///|
fn check_dbc_quoted_text(
  context : String,
  text : String,
) -> Result[Unit, DbcWriteError] {
  if dbc_quoted_text_is_valid(text) {
    Ok(())
  } else {
    Err(DbcWriteInvalidQuotedText(context, text))
  }
}

///|
fn check_signal_number(
  message_id : UInt,
  signal : Signal,
  field : String,
  value : Double,
) -> Result[Unit, DbcWriteError] {
  if value.is_nan() || value.is_inf() {
    Err(DbcWriteNonFiniteSignalNumber(message_id, signal.name, field))
  } else {
    Ok(())
  }
}

///|
fn signal_multiplex_text(
  message_id : UInt,
  signal : Signal,
) -> Result[String, DbcWriteError] {
  match signal.multiplex {
    Plain => Ok("")
    Multiplexer => Ok(" M")
    Multiplexed(value) =>
      if value < 0 {
        Err(DbcWriteNegativeMultiplexValue(message_id, signal.name, value))
      } else {
        Ok(" m\{value}")
      }
  }
}

///|
fn signal_byte_order_text(byte_order : ByteOrder) -> String {
  match byte_order {
    Motorola => "0"
    Intel => "1"
  }
}

///|
fn signal_sign_text(value_kind : ValueKind) -> String {
  match value_kind {
    Unsigned => "+"
    Signed => "-"
  }
}

///|
fn write_signal_line(
  message : Message,
  signal : Signal,
) -> Result[String, DbcWriteError] {
  match check_dbc_token("signal name", signal.name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match check_dbc_quoted_text("signal unit", signal.unit) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for receiver in signal.receivers {
    match check_dbc_token("signal receiver", receiver) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  match check_signal_number(message.id, signal, "factor", signal.factor) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match check_signal_number(message.id, signal, "offset", signal.offset) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match check_signal_number(message.id, signal, "minimum", signal.minimum) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match check_signal_number(message.id, signal, "maximum", signal.maximum) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let multiplex = match signal_multiplex_text(message.id, signal) {
    Err(error) => return Err(error)
    Ok(text) => text
  }
  let receivers = if signal.receivers.is_empty() {
    ""
  } else {
    " \{signal.receivers.join(",")}"
  }
  Ok(
    " SG_ \{signal.name}\{multiplex} : \{signal.start_bit}|\{signal.bit_length}@\{signal_byte_order_text(signal.byte_order)}\{signal_sign_text(signal.value_kind)} (\{signal.factor},\{signal.offset}) [\{signal.minimum}|\{signal.maximum}] \"\{signal.unit}\"\{receivers}",
  )
}

///|
fn write_message(
  lines : Array[String],
  message : Message,
) -> Result[Unit, DbcWriteError] {
  if dbc_message_id_parts(message.id) is None {
    return Err(DbcWriteInvalidMessageIdentifier(message.id))
  }
  match check_dbc_token("message name", message.name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match check_dbc_token("message transmitter", message.transmitter) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if message.payload_size < 0 || message.payload_size > 64 {
    return Err(DbcWriteInvalidPayloadSize(message.id, message.payload_size))
  }
  lines.push(
    "BO_ \{message.id} \{message.name}: \{message.payload_size} \{message.transmitter}",
  )
  for signal in message.signals {
    match write_signal_line(message, signal) {
      Err(error) => return Err(error)
      Ok(line) => lines.push(line)
    }
  }
  Ok(())
}

///|
fn write_message_transmitters(
  message : Message,
) -> Result[String?, DbcWriteError] {
  if message.additional_transmitters.is_empty() {
    return Ok(None)
  }
  let transmitters = [message.transmitter]
  for transmitter in message.additional_transmitters {
    match check_dbc_token("message transmitter", transmitter) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    for existing in transmitters {
      if existing == transmitter {
        return Err(DbcWriteDuplicateTransmitter(message.id, transmitter))
      }
    }
    transmitters.push(transmitter)
  }
  Ok(Some("BO_TX_BU_ \{message.id} : \{transmitters.join(",")};"))
}

///|
fn has_additional_transmitters(messages : Array[Message]) -> Bool {
  for message in messages {
    if !message.additional_transmitters.is_empty() {
      return true
    }
  }
  false
}

///|
fn write_value_table(
  lines : Array[String],
  table : ValueTable,
) -> Result[Unit, DbcWriteError] {
  if dbc_message_id_parts(table.message_id) is None {
    return Err(DbcWriteInvalidMessageIdentifier(table.message_id))
  }
  match check_dbc_token("value table signal name", table.signal_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if table.entries.is_empty() {
    return Err(DbcWriteEmptyValueTable(table.message_id, table.signal_name))
  }
  let parts = ["VAL_ \{table.message_id} \{table.signal_name}"]
  for entry in table.entries {
    match check_dbc_quoted_text("value description label", entry.label) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    parts.push("\{entry.value} \"\{entry.label}\"")
  }
  let body = parts.join(" ")
  lines.push("\{body};")
  Ok(())
}

///|
fn escape_dbc_comment(text : String) -> Result[String, DbcWriteError] {
  let chars : Array[Char] = []
  for char in text.iter() {
    if char == '\r' || char == '\n' {
      return Err(DbcWriteInvalidQuotedText("comment", text))
    }
    if char == '"' || char == '\\' {
      chars.push('\\')
    }
    chars.push(char)
  }
  Ok(String::from_array(chars))
}

///|
fn write_comment(comment : DbcComment) -> Result[String, DbcWriteError] {
  let prefix = match comment.target {
    DatabaseComment => "CM_"
    NodeComment(node) => {
      match check_dbc_token("comment node", node) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      "CM_ BU_ \{node}"
    }
    MessageComment(message_id) => {
      if dbc_message_id_parts(message_id) is None {
        return Err(DbcWriteInvalidMessageIdentifier(message_id))
      }
      "CM_ BO_ \{message_id}"
    }
    SignalComment(message_id, signal_name) => {
      if dbc_message_id_parts(message_id) is None {
        return Err(DbcWriteInvalidMessageIdentifier(message_id))
      }
      match check_dbc_token("comment signal", signal_name) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      "CM_ SG_ \{message_id} \{signal_name}"
    }
  }
  let text = match escape_dbc_comment(comment.text) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok("\{prefix} \"\{text}\";")
}

///|
/// Write the supported database model as deterministic DBC text. Structurally
/// invalid models should be checked with `Database::validate` before export;
/// this method reports values that cannot be represented by the parser syntax.
pub fn Database::to_dbc(self : Database) -> Result[String, DbcWriteError] {
  let lines : Array[String] = []
  let has_transmitter_section = has_additional_transmitters(self.messages)
  match self.version {
    Some(version) => {
      match check_dbc_quoted_text("database version", version) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      lines.push("VERSION \"\{version}\"")
      lines.push("")
    }
    None => ()
  }
  for node in self.nodes {
    match check_dbc_token("node name", node) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if self.nodes.is_empty() {
    lines.push("BU_:")
  } else {
    lines.push("BU_: \{self.nodes.join(" ")}")
  }
  if !self.messages.is_empty() ||
    !self.comments.is_empty() ||
    !self.value_tables.is_empty() {
    lines.push("")
  }
  for index, message in self.messages {
    match write_message(lines, message) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if index + 1 < self.messages.length() ||
      has_transmitter_section ||
      !self.comments.is_empty() ||
      !self.value_tables.is_empty() {
      lines.push("")
    }
  }
  for message in self.messages {
    match write_message_transmitters(message) {
      Err(error) => return Err(error)
      Ok(Some(line)) => lines.push(line)
      Ok(None) => ()
    }
  }
  if has_transmitter_section &&
    (!self.comments.is_empty() || !self.value_tables.is_empty()) {
    lines.push("")
  }
  for comment in self.comments {
    match write_comment(comment) {
      Err(error) => return Err(error)
      Ok(line) => lines.push(line)
    }
  }
  if !self.comments.is_empty() && !self.value_tables.is_empty() {
    lines.push("")
  }
  for index, table in self.value_tables {
    match write_value_table(lines, table) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if index + 1 < self.value_tables.length() {
      lines.push("")
    }
  }
  Ok(lines.join("\n"))
}
