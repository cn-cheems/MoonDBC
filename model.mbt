///|
/// DBC uses `@0` for Motorola bit order and `@1` for Intel bit order.
pub(all) enum ByteOrder {
  Motorola
  Intel
} derive(Eq, Debug)

///|
pub(all) enum ValueKind {
  Unsigned
  Signed
} derive(Eq, Debug)

///|
/// Physical storage selected by an optional `SIG_VALTYPE_` declaration.
pub(all) enum SignalValueType {
  Integer
  Float32
  Float64
} derive(Eq, Debug)

///|
pub(all) enum MultiplexRole {
  Plain
  Multiplexer
  Multiplexed(Int)
} derive(Eq, Debug)

///|
pub(all) struct Signal {
  name : String
  start_bit : Int
  bit_length : Int
  byte_order : ByteOrder
  value_kind : ValueKind
  value_type : SignalValueType
  factor : Double
  offset : Double
  minimum : Double
  maximum : Double
  unit : String
  receivers : Array[String]
  multiplex : MultiplexRole
} derive(Eq, Debug)

///|
pub(all) struct Message {
  /// Identifier as stored in DBC declarations. Extended frames set bit 31.
  id : UInt
  name : String
  payload_size : Int
  transmitter : String
  additional_transmitters : Array[String]
  signals : Array[Signal]
} derive(Eq, Debug)

///|
pub(all) struct ValueDescription {
  value : Int64
  label : String
} derive(Eq, Debug)

///|
pub(all) struct ValueTable {
  message_id : UInt
  signal_name : String
  entries : Array[ValueDescription]
} derive(Eq, Debug)

///|
pub(all) enum DbcCommentTarget {
  DatabaseComment
  NodeComment(String)
  MessageComment(UInt)
  SignalComment(UInt, String)
} derive(Eq, Debug)

///|
pub(all) struct DbcComment {
  target : DbcCommentTarget
  text : String
} derive(Eq, Debug)

///|
pub(all) struct Database {
  version : String?
  nodes : Array[String]
  messages : Array[Message]
  value_tables : Array[ValueTable]
  comments : Array[DbcComment]
} derive(Eq, Debug)

///|
pub(all) struct Diagnostic {
  line : Int
  column : Int
  code : String
  message : String
} derive(Eq, Debug)

///|
pub(all) struct ParseResult {
  database : Database
  diagnostics : Array[Diagnostic]
} derive(Eq, Debug)

///|
pub fn ParseResult::is_valid(self : ParseResult) -> Bool {
  self.diagnostics.is_empty()
}

///|
fn dbc_message_id_parts(id : UInt) -> (UInt, Bool)? {
  if id >= 0x80000000U {
    let frame_id = id & 0x7FFFFFFFU
    if frame_id <= 0x1FFFFFFFU {
      Some((frame_id, true))
    } else {
      None
    }
  } else if id <= 0x7FFU {
    Some((id, false))
  } else {
    None
  }
}

///|
fn dbc_message_id_from_frame(
  frame_id : UInt,
  is_extended_frame : Bool,
) -> UInt? {
  if is_extended_frame {
    if frame_id <= 0x1FFFFFFFU {
      Some(frame_id | 0x80000000U)
    } else {
      None
    }
  } else if frame_id <= 0x7FFU {
    Some(frame_id)
  } else {
    None
  }
}

///|
/// Return the arbitration identifier placed on the CAN bus.
pub fn Message::frame_id(self : Message) -> UInt {
  match dbc_message_id_parts(self.id) {
    Some((frame_id, _)) => frame_id
    None => self.id
  }
}

///|
/// Return whether the DBC identifier uses the bit-31 extended-frame marker.
pub fn Message::is_extended_frame(self : Message) -> Bool {
  match dbc_message_id_parts(self.id) {
    Some((_, extended)) => extended
    None => false
  }
}

///|
/// Find a message by the identifier stored in its DBC declaration. For a bus
/// arbitration identifier, use `find_can_message`.
pub fn Database::find_message(self : Database, id : UInt) -> Message? {
  for message in self.messages {
    if message.id == id {
      return Some(message)
    }
  }
  None
}

///|
/// Find a message by its bus arbitration identifier and frame format.
pub fn Database::find_can_message(
  self : Database,
  frame_id : UInt,
  is_extended_frame : Bool,
) -> Message? {
  let dbc_id = match dbc_message_id_from_frame(frame_id, is_extended_frame) {
    Some(value) => value
    None => return None
  }
  self.find_message(dbc_id)
}

///|
pub fn Message::find_signal(self : Message, name : StringView) -> Signal? {
  for signal in self.signals {
    if signal.name.view() == name {
      return Some(signal)
    }
  }
  None
}

///|
/// Return the primary transmitter followed by transmitters declared through
/// `BO_TX_BU_`.
pub fn Message::transmitters(self : Message) -> Array[String] {
  let result = [self.transmitter]
  for transmitter in self.additional_transmitters {
    result.push(transmitter)
  }
  result
}

///|
pub fn Message::is_transmitted_by(self : Message, node : StringView) -> Bool {
  if self.transmitter.view() == node {
    return true
  }
  for transmitter in self.additional_transmitters {
    if transmitter.view() == node {
      return true
    }
  }
  false
}

///|
pub fn Database::find_value_table(
  self : Database,
  message_id : UInt,
  signal_name : StringView,
) -> ValueTable? {
  for table in self.value_tables {
    if table.message_id == message_id && table.signal_name.view() == signal_name {
      return Some(table)
    }
  }
  None
}

///|
pub fn Database::find_comment(
  self : Database,
  target : DbcCommentTarget,
) -> DbcComment? {
  for comment in self.comments {
    if comment.target == target {
      return Some(comment)
    }
  }
  None
}

///|
pub fn Database::database_comment(self : Database) -> String? {
  match self.find_comment(DatabaseComment) {
    Some(comment) => Some(comment.text)
    None => None
  }
}

///|
pub fn Database::node_comment(self : Database, name : StringView) -> String? {
  match self.find_comment(NodeComment(name.to_owned())) {
    Some(comment) => Some(comment.text)
    None => None
  }
}

///|
pub fn Database::message_comment(self : Database, id : UInt) -> String? {
  match self.find_comment(MessageComment(id)) {
    Some(comment) => Some(comment.text)
    None => None
  }
}

///|
pub fn Database::can_message_comment(
  self : Database,
  frame_id : UInt,
  is_extended_frame : Bool,
) -> String? {
  match dbc_message_id_from_frame(frame_id, is_extended_frame) {
    Some(id) => self.message_comment(id)
    None => None
  }
}

///|
pub fn Database::signal_comment(
  self : Database,
  message_id : UInt,
  signal_name : StringView,
) -> String? {
  match self.find_comment(SignalComment(message_id, signal_name.to_owned())) {
    Some(comment) => Some(comment.text)
    None => None
  }
}

///|
pub fn Database::can_signal_comment(
  self : Database,
  frame_id : UInt,
  is_extended_frame : Bool,
  signal_name : StringView,
) -> String? {
  match dbc_message_id_from_frame(frame_id, is_extended_frame) {
    Some(id) => self.signal_comment(id, signal_name)
    None => None
  }
}

///|
pub fn ValueTable::find_label(self : ValueTable, value : Int64) -> String? {
  for entry in self.entries {
    if entry.value == value {
      return Some(entry.label)
    }
  }
  None
}

///|
pub fn Database::value_label(
  self : Database,
  message_id : UInt,
  signal_name : StringView,
  value : Int64,
) -> String? {
  match self.find_value_table(message_id, signal_name) {
    Some(table) => table.find_label(value)
    None => None
  }
}

///|
pub fn Database::can_value_label(
  self : Database,
  frame_id : UInt,
  is_extended_frame : Bool,
  signal_name : StringView,
  value : Int64,
) -> String? {
  match dbc_message_id_from_frame(frame_id, is_extended_frame) {
    Some(id) => self.value_label(id, signal_name, value)
    None => None
  }
}
