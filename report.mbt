///|
/// Describes how a database change affects consumers of the older DBC model.
pub(all) enum ChangeImpact {
  Breaking
  NonBreaking
  Informational
} derive(Eq, Debug)

///|
pub(all) struct ClassifiedChange {
  impact : ChangeImpact
  change : DatabaseChange
} derive(Eq, Debug)

///|
pub(all) struct CompatibilityReport {
  changes : Array[ClassifiedChange]
  breaking_count : Int
  non_breaking_count : Int
  informational_count : Int
} derive(Eq, Debug)

///|
fn version_text(version : String?) -> String {
  match version {
    Some(value) => "\"\{value}\""
    None => "an unspecified version"
  }
}

///|
fn impact_label(impact : ChangeImpact) -> String {
  match impact {
    Breaking => "Breaking"
    NonBreaking => "Non-breaking"
    Informational => "Informational"
  }
}

///|
/// Classify a change from the perspective of software built against the older
/// database. Additions remain compatible, while removals and changed layouts
/// require consumers to review or update their assumptions.
pub fn DatabaseChange::impact(self : DatabaseChange) -> ChangeImpact {
  match self {
    VersionChangedChange(_, _)
    | NodesChangedChange(_, _)
    | CommentAddedChange(_)
    | CommentRemovedChange(_)
    | CommentModifiedChange(_, _, _) => Informational
    MessageAddedChange(_)
    | SignalAddedChange(_, _)
    | ValueTableAddedChange(_) => NonBreaking
    MessageRemovedChange(_)
    | MessageMetadataChangedChange(_, _, _)
    | SignalRemovedChange(_, _)
    | SignalModifiedChange(_, _, _, _)
    | ValueTableRemovedChange(_)
    | ValueTableModifiedChange(_, _, _, _) => Breaking
  }
}

///|
fn comment_target_text(target : DbcCommentTarget) -> String {
  match target {
    DatabaseComment => "the database"
    NodeComment(node) => "node \{node}"
    MessageComment(message_id) => "message \{message_id}"
    SignalComment(message_id, signal_name) =>
      "signal \{signal_name} in message \{message_id}"
  }
}

///|
/// Render a concise sentence suitable for logs, reviews, and release notes.
pub fn DatabaseChange::summary(self : DatabaseChange) -> String {
  match self {
    VersionChangedChange(before, after) =>
      "DBC version changed from \{version_text(before)} to \{version_text(after)}."
    NodesChangedChange(before, after) =>
      "Node list changed (\{before.length()} -> \{after.length()})."
    CommentAddedChange(comment) =>
      "Comment for \{comment_target_text(comment.target)} was added."
    CommentRemovedChange(comment) =>
      "Comment for \{comment_target_text(comment.target)} was removed."
    CommentModifiedChange(target, _, _) =>
      "Comment for \{comment_target_text(target)} was modified."
    MessageAddedChange(message) =>
      "Message \{message.id} (\{message.name}) was added."
    MessageRemovedChange(message) =>
      "Message \{message.id} (\{message.name}) was removed."
    MessageMetadataChangedChange(id, before, after) =>
      "Message \{id} metadata changed from \{before.name}/\{before.payload_size} bytes/\{before.additional_transmitters.length() + 1} transmitter(s) to \{after.name}/\{after.payload_size} bytes/\{after.additional_transmitters.length() + 1} transmitter(s)."
    SignalAddedChange(message_id, signal) =>
      "Signal \{signal.name} in message \{message_id} was added."
    SignalRemovedChange(message_id, signal) =>
      "Signal \{signal.name} in message \{message_id} was removed."
    SignalModifiedChange(message_id, name, _, _) =>
      "Signal \{name} in message \{message_id} was modified."
    ValueTableAddedChange(table) =>
      "Value table for \{table.signal_name} in message \{table.message_id} was added."
    ValueTableRemovedChange(table) =>
      "Value table for \{table.signal_name} in message \{table.message_id} was removed."
    ValueTableModifiedChange(message_id, signal_name, _, _) =>
      "Value table for \{signal_name} in message \{message_id} was modified."
  }
}

///|
/// Compare two databases and summarize the compatibility impact of every
/// detected model change.
pub fn Database::compatibility_report(
  self : Database,
  newer : Database,
) -> CompatibilityReport {
  let changes : Array[ClassifiedChange] = []
  let mut breaking_count = 0
  let mut non_breaking_count = 0
  let mut informational_count = 0
  for change in self.diff(newer) {
    let impact = change.impact()
    match impact {
      Breaking => breaking_count += 1
      NonBreaking => non_breaking_count += 1
      Informational => informational_count += 1
    }
    changes.push({ impact, change, })
  }
  { changes, breaking_count, non_breaking_count, informational_count, }
}

///|
pub fn CompatibilityReport::has_changes(self : CompatibilityReport) -> Bool {
  !self.changes.is_empty()
}

///|
/// A report remains backward compatible when it contains no breaking changes.
pub fn CompatibilityReport::is_backward_compatible(
  self : CompatibilityReport,
) -> Bool {
  self.breaking_count == 0
}

///|
/// Render a deterministic Markdown report for pull requests and CI artifacts.
pub fn CompatibilityReport::to_markdown(self : CompatibilityReport) -> String {
  let lines = [
    "# DBC Compatibility Report",
    "",
    "- Breaking changes: \{self.breaking_count}",
    "- Non-breaking changes: \{self.non_breaking_count}",
    "- Informational changes: \{self.informational_count}",
    "",
  ]
  if self.changes.is_empty() {
    lines.push("No changes detected.")
  } else {
    lines.push("## Changes")
    lines.push("")
    for classified in self.changes {
      lines.push(
        "- **\{impact_label(classified.impact)}**: \{classified.change.summary()}",
      )
    }
  }
  lines.join("\n")
}
