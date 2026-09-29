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
pub(all) struct CommentSourceLocation {
  target : DbcCommentTarget
  declaration : SourceSpan
} derive(Eq, Debug)

///|
pub(all) struct ValueTableSourceLocation {
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
  comments : Array[CommentSourceLocation]
  value_tables : Array[ValueTableSourceLocation]
} derive(Eq, Debug)

///|
pub(all) struct SourceParseResult {
  database : Database
  diagnostics : Array[Diagnostic]
  source_map : DbcSourceMap
} derive(Eq, Debug)

///|
pub(all) struct LocatedValidationIssue {
  issue : ValidationIssue
  source : SourceSpan?
} derive(Eq, Debug)

///|
pub(all) struct LocatedDatabaseChange {
  change : DatabaseChange
  before : SourceSpan?
  after : SourceSpan?
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

///|
pub fn DbcSourceMap::find_comment(
  self : DbcSourceMap,
  target : DbcCommentTarget,
) -> SourceSpan? {
  for location in self.comments {
    if location.target == target {
      return Some(location.declaration)
    }
  }
  None
}

///|
pub fn DbcSourceMap::find_value_table(
  self : DbcSourceMap,
  message_id : UInt,
  signal_name : StringView,
) -> SourceSpan? {
  for location in self.value_tables {
    if location.message_id == message_id &&
      location.signal_name.view() == signal_name {
      return Some(location.declaration)
    }
  }
  None
}

///|
fn change_source(
  source_map : DbcSourceMap,
  change : DatabaseChange,
) -> SourceSpan? {
  match change {
    VersionChangedChange(_, _) | NodesChangedChange(_, _) => None
    CommentAddedChange(comment) | CommentRemovedChange(comment) =>
      source_map.find_comment(comment.target)
    CommentModifiedChange(target, _, _) => source_map.find_comment(target)
    MessageAddedChange(message) | MessageRemovedChange(message) =>
      source_map.find_message(message.id)
    MessageMetadataChangedChange(id, _, _) => source_map.find_message(id)
    SignalAddedChange(id, signal) | SignalRemovedChange(id, signal) =>
      source_map.find_signal(id, signal.name)
    SignalModifiedChange(id, name, _, _) => source_map.find_signal(id, name)
    ValueTableAddedChange(table) | ValueTableRemovedChange(table) =>
      source_map.find_value_table(table.message_id, table.signal_name)
    ValueTableModifiedChange(id, name, _, _) =>
      source_map.find_value_table(id, name)
  }
}

///|
/// Compare parsed DBCs and attach the old and new declaration ranges to each
/// change. Global metadata has no declaration mapping and returns `None`.
pub fn SourceParseResult::diff_with_locations(
  self : SourceParseResult,
  newer : SourceParseResult,
) -> Array[LocatedDatabaseChange] {
  let result : Array[LocatedDatabaseChange] = []
  for change in self.database.diff(newer.database) {
    let old_location = match change {
      CommentAddedChange(_)
      | MessageAddedChange(_)
      | SignalAddedChange(_, _)
      | ValueTableAddedChange(_) => None
      _ => change_source(self.source_map, change)
    }
    let new_location = match change {
      CommentRemovedChange(_)
      | MessageRemovedChange(_)
      | SignalRemovedChange(_, _)
      | ValueTableRemovedChange(_) => None
      _ => change_source(newer.source_map, change)
    }
    result.push({ change, before: old_location, after: new_location, })
  }
  result
}

///|
fn validation_issue_source(
  source_map : DbcSourceMap,
  issue : ValidationIssue,
) -> SourceSpan? {
  match issue {
    InvalidMessageIdentifierIssue(id) => source_map.find_message(id)
    DuplicateMessageIdIssue(id) => source_map.find_message(id)
    InvalidPayloadSizeIssue(id, _) => source_map.find_message(id)
    MultipleMultiplexersIssue(id) => source_map.find_message(id)
    DuplicateMessageTransmitterIssue(id, _) => source_map.find_message(id)
    DuplicateSignalNameIssue(id, name) => source_map.find_signal(id, name)
    InvalidSignalLayoutIssue(id, name, _, _) => source_map.find_signal(id, name)
    InvalidSignalValueTypeIssue(id, name, _, _) =>
      source_map.find_signal(id, name)
    FloatingMultiplexerIssue(id, name, _) => source_map.find_signal(id, name)
    SignalOutsidePayloadIssue(id, name) => source_map.find_signal(id, name)
    InvalidScaleIssue(id, name, _, _) => source_map.find_signal(id, name)
    InvalidPhysicalRangeIssue(id, name, _, _) =>
      source_map.find_signal(id, name)
    MissingMultiplexerIssue(id, name) => source_map.find_signal(id, name)
    MultiplexSelectorOutOfRangeIssue(id, name, _) =>
      source_map.find_signal(id, name)
    InvalidMultiplexRangeIssue(id, name, _, _) =>
      source_map.find_signal(id, name)
    UnknownMultiplexSelectorIssue(id, name, _) =>
      source_map.find_signal(id, name)
    OverlappingSignalsIssue(id, _, right) => source_map.find_signal(id, right)
    DuplicateCommentIssue(target) => source_map.find_comment(target)
    UnknownCommentNodeIssue(node) => source_map.find_comment(NodeComment(node))
    UnknownCommentMessageIssue(id) =>
      source_map.find_comment(MessageComment(id))
    UnknownCommentSignalIssue(id, name) =>
      source_map.find_comment(SignalComment(id, name))
  }
}

///|
/// Validate the parsed model and attach declaration locations where available.
/// Overlap issues point to the later signal; comment issues without declaration
/// locations retain `None` rather than inventing a source position.
pub fn SourceParseResult::locate_validation_issues(
  self : SourceParseResult,
) -> Array[LocatedValidationIssue] {
  self.database
  .validate()
  .map(issue => {
    issue,
    source: validation_issue_source(self.source_map, issue),
  })
}
