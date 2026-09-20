///|
/// A half-open source range. Lines and columns are one-based; the end position
/// points immediately after the declaration.
pub(all) struct SourceSpan {
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
} derive(Eq, Debug)

///|
pub(all) struct MessageSourceLocation {
  message_id : UInt
  declaration : SourceSpan
} derive(Eq, Debug)

///|
pub(all) struct SignalSourceLocation {
  message_id : UInt
  signal_name : String
  declaration : SourceSpan
} derive(Eq, Debug)

///|
/// Source locations are kept separately from the semantic model so manually
/// constructed databases and existing `parse` callers remain source-agnostic.
pub(all) struct DbcSourceMap {
  messages : Array[MessageSourceLocation]
  signals : Array[SignalSourceLocation]
} derive(Eq, Debug)

///|
pub(all) struct SourceParseResult {
  database : Database
  diagnostics : Array[Diagnostic]
  source_map : DbcSourceMap
} derive(Eq, Debug)

///|
pub fn SourceParseResult::is_valid(self : SourceParseResult) -> Bool {
  self.diagnostics.is_empty()
}

///|
pub fn DbcSourceMap::find_message(
  self : DbcSourceMap,
  message_id : UInt,
) -> SourceSpan? {
  for location in self.messages {
    if location.message_id == message_id {
      return Some(location.declaration)
    }
  }
  None
}

///|
pub fn DbcSourceMap::find_signal(
  self : DbcSourceMap,
  message_id : UInt,
  signal_name : StringView,
) -> SourceSpan? {
  for location in self.signals {
    if location.message_id == message_id &&
      location.signal_name.view() == signal_name {
      return Some(location.declaration)
    }
  }
  None
}
