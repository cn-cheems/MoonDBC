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
    MultiplexedRanges(_, ranges) =>
      for range_index, range in ranges {
        lines.push(
          "pub const \{prefix}_MULTIPLEX_RANGE_\{range_index}_START : Int = \{range.start}",
        )
        lines.push(
          "pub const \{prefix}_MULTIPLEX_RANGE_\{range_index}_END : Int = \{range.end}",
        )
      }
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

///|
fn codec_byte_order(order : ByteOrder) -> String {
  match order {
    Intel => "@moondbc.Intel"
    Motorola => "@moondbc.Motorola"
  }
}

///|
fn codec_value_kind(kind : ValueKind) -> String {
  match kind {
    Unsigned => "@moondbc.Unsigned"
    Signed => "@moondbc.Signed"
  }
}

///|
fn codec_value_type(value_type : SignalValueType) -> String {
  match value_type {
    Integer => "@moondbc.Integer"
    Float32 => "@moondbc.Float32"
    Float64 => "@moondbc.Float64"
  }
}

///|
fn append_signal_codec(
  lines : Array[String],
  message : Message,
  signal : Signal,
  index : Int,
) -> Unit {
  let name = signal_codegen_prefix(message, signal, index).to_lower()
  lines.push("///|")
  lines.push("/// Signal \{index} of DBC message \{message.id}.")
  lines.push("fn \{name}_signal() -> @moondbc.Signal {")
  lines.push("  {")
  lines.push("    name: \"\",")
  lines.push("    start_bit: \{signal.start_bit},")
  lines.push("    bit_length: \{signal.bit_length},")
  lines.push("    byte_order: \{codec_byte_order(signal.byte_order)},")
  lines.push("    value_kind: \{codec_value_kind(signal.value_kind)},")
  lines.push("    value_type: \{codec_value_type(signal.value_type)},")
  lines.push("    factor: \{signal.factor},")
  lines.push("    offset: \{signal.offset},")
  lines.push("    minimum: \{signal.minimum},")
  lines.push("    maximum: \{signal.maximum},")
  lines.push("    unit: \"\",")
  lines.push("    receivers: [],")
  lines.push("    multiplex: @moondbc.Plain,")
  lines.push("  }")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push("pub fn decode_\{name}(")
  lines.push("  payload : BytesView,")
  lines.push(") -> Result[Double, @moondbc.DecodeError] {")
  lines.push("  \{name}_signal().decode(payload)")
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push("pub fn encode_\{name}(")
  lines.push("  payload : BytesView,")
  lines.push("  physical : Double,")
  lines.push(") -> Result[Bytes, @moondbc.EncodeError] {")
  lines.push("  \{name}_signal().encode(payload, physical)")
  lines.push("}")
  lines.push("")
}

///|
/// Generate named, signal-level encode and decode functions that do not parse
/// DBC text at runtime. The destination package must import this library as
/// `@moondbc`. Multiplex branch selection remains the caller's responsibility;
/// use `Message::decode_frame` and `Message::encode_frame` for whole frames.
pub fn Database::generate_moonbit_signal_codecs(
  self : Database,
) -> Result[String, String] {
  if !self.validate().is_empty() {
    return Err("cannot generate codecs from an invalid DBC model")
  }
  let lines = [
    "// MoonDBC signal codecs. Import cn-cheems/moondbc as @moondbc.", "",
  ]
  for message in self.messages {
    for index, signal in message.signals {
      append_signal_codec(lines, message, signal, index)
    }
  }
  if lines.length() > 1 && lines[lines.length() - 1] == "" {
    let _ = lines.pop()
  }
  Ok(lines.join("\n"))
}
