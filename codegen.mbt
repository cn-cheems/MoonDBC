///|
fn codegen_identifier(source : StringView) -> String {
  let chars : Array[Char] = []
  let mut separator = true
  for char in source.to_upper().iter() {
    let allowed = (char >= 'A' && char <= 'Z') || (char >= '0' && char <= '9')
    if allowed {
      chars.push(char)
      separator = false
    } else if !separator && !chars.is_empty() {
      chars.push('_')
      separator = true
    }
  }
  if chars.length() > 0 && chars[chars.length() - 1] == '_' {
    let _ = chars.pop()
  }
  if chars.is_empty() {
    "UNNAMED"
  } else {
    String::from_array(chars)
  }
}

///|
fn message_codegen_prefix(message : Message) -> String {
  "DBC_\{codegen_identifier(message.name)}_\{message.id}"
}

///|
fn signal_codegen_prefix(
  message : Message,
  signal : Signal,
  index : Int,
) -> String {
  "\{message_codegen_prefix(message)}_\{codegen_identifier(signal.name)}_\{index}"
}

///|
fn append_signal_constants(
  lines : Array[String],
  message : Message,
  signal : Signal,
  index : Int,
) -> Unit {
  let prefix = signal_codegen_prefix(message, signal, index)
  lines.push("/// Signal \{signal.name} in message \{message.name}.")
  lines.push("pub const \{prefix}_START_BIT : Int = \{signal.start_bit}")
  lines.push("pub const \{prefix}_BIT_LENGTH : Int = \{signal.bit_length}")
  lines.push(
    "pub const \{prefix}_IS_INTEL : Bool = \{signal.byte_order == Intel}",
  )
  lines.push(
    "pub const \{prefix}_IS_SIGNED : Bool = \{signal.value_kind == Signed}",
  )
  match signal.value_type {
    Integer => ()
    Float32 => lines.push("pub const \{prefix}_IS_FLOAT32 : Bool = true")
    Float64 => lines.push("pub const \{prefix}_IS_FLOAT64 : Bool = true")
  }
  lines.push("pub const \{prefix}_FACTOR : Double = \{signal.factor}")
  lines.push("pub const \{prefix}_OFFSET : Double = \{signal.offset}")
  lines.push("pub const \{prefix}_MINIMUM : Double = \{signal.minimum}")
  lines.push("pub const \{prefix}_MAXIMUM : Double = \{signal.maximum}")
  match signal.multiplex {
    Plain => ()
    Multiplexer =>
      lines.push("pub const \{prefix}_IS_MULTIPLEXER : Bool = true")
    Multiplexed(value) =>
      lines.push("pub const \{prefix}_MULTIPLEX_VALUE : Int = \{value}")
  }
  lines.push("")
}

///|
fn append_message_constants(lines : Array[String], message : Message) -> Unit {
  let prefix = message_codegen_prefix(message)
  let identity = if message.is_extended_frame() {
    "extended \{message.frame_id()}; DBC id \{message.id}"
  } else {
    message.id.to_string()
  }
  lines.push("/// Message \{message.name} (\{identity}).")
  lines.push("pub const \{prefix}_ID : UInt = \{message.frame_id()}U")
  lines.push(
    "pub const \{prefix}_IS_EXTENDED_FRAME : Bool = \{message.is_extended_frame()}",
  )
  lines.push("pub const \{prefix}_PAYLOAD_SIZE : Int = \{message.payload_size}")
  lines.push("")
  for index, signal in message.signals {
    append_signal_constants(lines, message, signal, index)
  }
}

///|
fn append_value_constants(lines : Array[String], table : ValueTable) -> Unit {
  for index, entry in table.entries {
    let prefix = "DBC_VALUE_\{table.message_id}_\{codegen_identifier(table.signal_name)}_\{codegen_identifier(entry.label)}_\{index}"
    lines.push(
      "/// Value \{entry.label} for signal \{table.signal_name} in message \{table.message_id}.",
    )
    lines.push("pub const \{prefix} : Int64 = \{entry.value}L")
    lines.push("")
  }
}

///|
/// Generate standalone MoonBit constants for message identifiers, payload
/// sizes, signal layouts, scaling parameters, multiplexing, and value tables.
/// Names are normalized and include stable numeric suffixes to avoid clashes.
pub fn Database::generate_moonbit_constants(self : Database) -> String {
  let lines = ["// MoonDBC static CAN metadata.", ""]
  for message in self.messages {
    append_message_constants(lines, message)
  }
  for table in self.value_tables {
    append_value_constants(lines, table)
  }
  if lines.length() > 1 && lines[lines.length() - 1] == "" {
    let _ = lines.pop()
  }
  lines.join("\n")
}
