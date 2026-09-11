///|
pub(all) enum TraceError {
  TraceFrameTextError(CanFrameTextError)
  TraceFrameDecodeError(FrameDecodeError)
} derive(Eq, Debug)

///|
pub(all) struct TraceDiagnostic {
  line : Int
  text : String
  error : TraceError
} derive(Eq, Debug)

///|
pub(all) struct DecodedTraceFrame {
  line : Int
  frame : CanFrame
  decoded : DecodedMessage
} derive(Eq, Debug)

///|
pub(all) struct TraceDecodeResult {
  frames : Array[DecodedTraceFrame]
  diagnostics : Array[TraceDiagnostic]
} derive(Eq, Debug)

///|
pub fn TraceDecodeResult::is_valid(self : TraceDecodeResult) -> Bool {
  self.diagnostics.is_empty()
}

///|
/// Decode compact SocketCAN frames line by line. Blank lines and lines starting
/// with `//` are ignored. Invalid or undecodable lines are retained as
/// diagnostics without preventing later frames from being processed.
pub fn Database::decode_trace(
  self : Database,
  source : StringView,
) -> TraceDecodeResult {
  let frames : Array[DecodedTraceFrame] = []
  let diagnostics : Array[TraceDiagnostic] = []
  let mut line_number = 0
  for raw_line in source.split("\n") {
    line_number += 1
    let line = raw_line.trim(chars=" \t\r")
    if line.is_empty() || line.has_prefix("//") {
      continue
    }
    match parse_can_frame(line) {
      Err(error) =>
        diagnostics.push({
          line: line_number,
          text: line.to_owned(),
          error: TraceFrameTextError(error),
        })
      Ok(frame) =>
        match self.decode_can_frame(frame) {
          Err(error) =>
            diagnostics.push({
              line: line_number,
              text: line.to_owned(),
              error: TraceFrameDecodeError(error),
            })
          Ok(decoded) => frames.push({ line: line_number, frame, decoded, })
        }
    }
  }
  { frames, diagnostics, }
}

///|
fn trace_csv_text(value : StringView) -> String {
  let chars : Array[Char] = ['"']
  for char in value.iter() {
    if char == '"' {
      chars.push('"')
    }
    chars.push(char)
  }
  chars.push('"')
  String::from_array(chars)
}

///|
fn trace_raw_text(raw : RawValue) -> String {
  match raw {
    UnsignedRaw(value) => value.to_string()
    SignedRaw(value) => value.to_string()
  }
}

///|
fn trace_label_text(label : String?) -> String {
  match label {
    Some(value) => value
    None => ""
  }
}

///|
/// Export successfully decoded trace signals as RFC 4180-style CSV rows.
/// Text fields are always quoted and embedded quotes are doubled.
pub fn TraceDecodeResult::to_csv(
  self : TraceDecodeResult,
) -> Result[String, CanFrameTextError] {
  let lines = ["line,frame,message,signal,raw,physical,unit,label"]
  for record in self.frames {
    let frame_text = match record.frame.to_text() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    for signal in record.decoded.signals {
      lines.push(
        "\{record.line},\{frame_text},\{trace_csv_text(record.decoded.name)},\{trace_csv_text(signal.name)},\{trace_raw_text(signal.raw)},\{signal.physical},\{trace_csv_text(signal.unit)},\{trace_csv_text(trace_label_text(signal.label))}",
      )
    }
  }
  Ok(lines.join("\r\n"))
}
