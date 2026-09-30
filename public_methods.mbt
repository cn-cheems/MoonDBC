///|
/// Keep trait-derived convenience methods available as regular public methods.
pub extend CanFrame with Eq::{not_equal, equal}

///|
pub extend CanFrame with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CanFrameTextError with Eq::{not_equal, equal}

///|
pub extend CanFrameTextError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CanLogRecord with Eq::{not_equal, equal}

///|
pub extend CanLogRecord with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CanLogTextError with Eq::{not_equal, equal}

///|
pub extend CanLogTextError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CliMode with Eq::{not_equal, equal}

///|
pub extend CliMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CliOutput with Eq::{not_equal, equal}

///|
pub extend CliOutput with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LocatedValidationIssue with Eq::{not_equal, equal}

///|
pub extend LocatedValidationIssue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LocatedDatabaseChange with Eq::{not_equal, equal}

///|
pub extend LocatedDatabaseChange with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RawValue with Eq::{not_equal, equal}

///|
pub extend RawValue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DecodeError with Eq::{not_equal, equal}

///|
pub extend DecodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MessageMetadata with Eq::{not_equal, equal}

///|
pub extend MessageMetadata with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DatabaseChange with Eq::{not_equal, equal}

///|
pub extend DatabaseChange with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EncodeError with Eq::{not_equal, equal}

///|
pub extend EncodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DecodedSignal with Eq::{not_equal, equal}

///|
pub extend DecodedSignal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DecodedMessage with Eq::{not_equal, equal}

///|
pub extend DecodedMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameDecodeError with Eq::{not_equal, equal}

///|
pub extend FrameDecodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SignalAssignment with Eq::{not_equal, equal}

///|
pub extend SignalAssignment with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameEncodeError with Eq::{not_equal, equal}

///|
pub extend FrameEncodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ByteOrder with Eq::{not_equal, equal}

///|
pub extend ByteOrder with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValueKind with Eq::{not_equal, equal}

///|
pub extend ValueKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SignalValueType with Eq::{not_equal, equal}

///|
pub extend SignalValueType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MultiplexRole with Eq::{not_equal, equal}

///|
pub extend MultiplexRole with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MultiplexRange with Eq::{not_equal, equal}

///|
pub extend MultiplexRange with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributeScope with Eq::{not_equal, equal}

///|
pub extend DbcAttributeScope with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributeType with Eq::{not_equal, equal}

///|
pub extend DbcAttributeType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributeValue with Eq::{not_equal, equal}

///|
pub extend DbcAttributeValue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributeTarget with Eq::{not_equal, equal}

///|
pub extend DbcAttributeTarget with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributeDefinition with Eq::{not_equal, equal}

///|
pub extend DbcAttributeDefinition with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributeDefault with Eq::{not_equal, equal}

///|
pub extend DbcAttributeDefault with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributeAssignment with Eq::{not_equal, equal}

///|
pub extend DbcAttributeAssignment with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcAttributes with Eq::{not_equal, equal}

///|
pub extend DbcAttributes with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Signal with Eq::{not_equal, equal}

///|
pub extend Signal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Message with Eq::{not_equal, equal}

///|
pub extend Message with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValueDescription with Eq::{not_equal, equal}

///|
pub extend ValueDescription with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValueTable with Eq::{not_equal, equal}

///|
pub extend ValueTable with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SignalGroup with Eq::{not_equal, equal}

///|
pub extend SignalGroup with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcCommentTarget with Eq::{not_equal, equal}

///|
pub extend DbcCommentTarget with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcComment with Eq::{not_equal, equal}

///|
pub extend DbcComment with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Database with Eq::{not_equal, equal}

///|
pub extend Database with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{not_equal, equal}

///|
pub extend Diagnostic with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParseResult with Eq::{not_equal, equal}

///|
pub extend ParseResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChangeImpact with Eq::{not_equal, equal}

///|
pub extend ChangeImpact with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ClassifiedChange with Eq::{not_equal, equal}

///|
pub extend ClassifiedChange with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompatibilityReport with Eq::{not_equal, equal}

///|
pub extend CompatibilityReport with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TraceError with Eq::{not_equal, equal}

///|
pub extend TraceError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TraceDiagnostic with Eq::{not_equal, equal}

///|
pub extend TraceDiagnostic with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DecodedTraceFrame with Eq::{not_equal, equal}

///|
pub extend DecodedTraceFrame with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TraceDecodeResult with Eq::{not_equal, equal}

///|
pub extend TraceDecodeResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValidationIssue with Eq::{not_equal, equal}

///|
pub extend ValidationIssue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DbcWriteError with Eq::{not_equal, equal}

///|
pub extend DbcWriteError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SourceSpan with Eq::{not_equal, equal}

///|
pub extend SourceSpan with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MessageSourceLocation with Eq::{not_equal, equal}

///|
pub extend MessageSourceLocation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SignalSourceLocation with Eq::{not_equal, equal}

///|
pub extend SignalSourceLocation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommentSourceLocation with Eq::{not_equal, equal}

///|
pub extend CommentSourceLocation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValueTableSourceLocation with Eq::{not_equal, equal}

///|
pub extend ValueTableSourceLocation with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend SignalGroupSourceLocation with Eq::{not_equal, equal}

///|
pub extend SignalGroupSourceLocation with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend DbcSourceMap with Eq::{not_equal, equal}

///|
pub extend DbcSourceMap with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SourceParseResult with Eq::{not_equal, equal}

///|
pub extend SourceParseResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameLayoutCellKind with Eq::{not_equal, equal}

///|
pub extend FrameLayoutCellKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameLayoutOwner with Eq::{not_equal, equal}

///|
pub extend FrameLayoutOwner with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameLayoutCell with Eq::{not_equal, equal}

///|
pub extend FrameLayoutCell with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameLayoutIssue with Eq::{not_equal, equal}

///|
pub extend FrameLayoutIssue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameLayoutAnalysis with Eq::{not_equal, equal}

///|
pub extend FrameLayoutAnalysis with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FrameLayoutError with Eq::{not_equal, equal}

///|
pub extend FrameLayoutError with @moonbitlang/core/debug.Debug::{to_repr}
