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
  signals : Array[Signal]
} derive(Eq, Debug)

///|
pub(all) struct Database {
  version : String?
  nodes : Array[String]
  messages : Array[Message]
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
