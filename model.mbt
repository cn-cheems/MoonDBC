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
pub fn Database::find_message(self : Database, id : UInt) -> Message? {
  for message in self.messages {
    if message.id == id {
      return Some(message)
    }
  }
  None
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
