///|
pub(all) struct MessageMetadata {
  name : String
  payload_size : Int
  transmitter : String
} derive(Eq, Debug)

///|
pub(all) enum DatabaseChange {
  VersionChangedChange(String?, String?)
  NodesChangedChange(Array[String], Array[String])
  MessageAddedChange(Message)
  MessageRemovedChange(Message)
  MessageMetadataChangedChange(UInt, MessageMetadata, MessageMetadata)
  SignalAddedChange(UInt, Signal)
  SignalRemovedChange(UInt, Signal)
  SignalModifiedChange(UInt, String, Signal, Signal)
  ValueTableAddedChange(ValueTable)
  ValueTableRemovedChange(ValueTable)
  ValueTableModifiedChange(UInt, String, ValueTable, ValueTable)
} derive(Eq, Debug)

///|
fn message_metadata(message : Message) -> MessageMetadata {
  {
    name: message.name,
    payload_size: message.payload_size,
    transmitter: message.transmitter,
  }
}

///|
fn find_signal_in(message : Message, name : StringView) -> Signal? {
  for signal in message.signals {
    if signal.name.view() == name {
      return Some(signal)
    }
  }
  None
}

///|
fn diff_message(
  before : Message,
  after : Message,
  changes : Array[DatabaseChange],
) -> Unit {
  let before_metadata = message_metadata(before)
  let after_metadata = message_metadata(after)
  if before_metadata != after_metadata {
    changes.push(
      MessageMetadataChangedChange(before.id, before_metadata, after_metadata),
    )
  }
  for signal in before.signals {
    match find_signal_in(after, signal.name) {
      None => changes.push(SignalRemovedChange(before.id, signal))
      Some(after_signal) =>
        if signal != after_signal {
          changes.push(
            SignalModifiedChange(before.id, signal.name, signal, after_signal),
          )
        }
    }
  }
  for signal in after.signals {
    if find_signal_in(before, signal.name) is None {
      changes.push(SignalAddedChange(before.id, signal))
    }
  }
}

///|
fn diff_value_tables(
  before : Database,
  after : Database,
  changes : Array[DatabaseChange],
) -> Unit {
  for table in before.value_tables {
    match after.find_value_table(table.message_id, table.signal_name) {
      None => changes.push(ValueTableRemovedChange(table))
      Some(after_table) =>
        if table != after_table {
          changes.push(
            ValueTableModifiedChange(
              table.message_id,
              table.signal_name,
              table,
              after_table,
            ),
          )
        }
    }
  }
  for table in after.value_tables {
    if before.find_value_table(table.message_id, table.signal_name) is None {
      changes.push(ValueTableAddedChange(table))
    }
  }
}

///|
/// Compare this database with a newer database. Changes are returned in a
/// deterministic order: global metadata, removals/modifications, then additions.
pub fn Database::diff(
  self : Database,
  newer : Database,
) -> Array[DatabaseChange] {
  let changes : Array[DatabaseChange] = []
  if self.version != newer.version {
    changes.push(VersionChangedChange(self.version, newer.version))
  }
  if self.nodes != newer.nodes {
    changes.push(NodesChangedChange(self.nodes, newer.nodes))
  }
  for message in self.messages {
    match newer.find_message(message.id) {
      None => changes.push(MessageRemovedChange(message))
      Some(newer_message) => diff_message(message, newer_message, changes)
    }
  }
  for message in newer.messages {
    if self.find_message(message.id) is None {
      changes.push(MessageAddedChange(message))
    }
  }
  diff_value_tables(self, newer, changes)
  changes
}
