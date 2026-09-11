///|
/// A compact CAN frame with optional candump timestamp and interface metadata.
pub(all) struct CanLogRecord {
  timestamp : String?
  interface_name : String?
  frame : CanFrame
} derive(Eq, Debug)

///|
pub(all) enum CanLogTextError {
  CanLogInvalidFieldCount(Int)
  CanLogInvalidTimestamp(String)
  CanLogInvalidInterface(String)
  CanLogTimestampWithoutInterface
  CanLogFrameTextError(CanFrameTextError)
} derive(Eq, Debug)

///|
fn can_log_fields(text : StringView) -> Array[String] {
  let fields : Array[String] = []
  let current : Array[Char] = []
  for char in text.iter() {
    if char == ' ' || char == '\t' || char == '\r' || char == '\n' {
      if !current.is_empty() {
        fields.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(char)
    }
  }
  if !current.is_empty() {
    fields.push(String::from_array(current))
  }
  fields
}

///|
fn can_log_timestamp_is_valid(timestamp : StringView) -> Bool {
  if timestamp.is_empty() {
    return false
  }
  match parse_double(timestamp) {
    Some(value) => !value.is_nan() && !value.is_inf()
    None => false
  }
}

///|
fn parse_can_log_timestamp(text : StringView) -> String? {
  if text.length() < 3 || !text.has_prefix("(") || !text.has_suffix(")") {
    return None
  }
  let timestamp = text[1:text.length() - 1]
  if can_log_timestamp_is_valid(timestamp) {
    Some(timestamp.to_owned())
  } else {
    None
  }
}

///|
fn can_log_interface_is_valid(interface_name : StringView) -> Bool {
  if interface_name.is_empty() {
    return false
  }
  for char in interface_name.iter() {
    let valid = (char >= 'a' && char <= 'z') ||
      (char >= 'A' && char <= 'Z') ||
      (char >= '0' && char <= '9') ||
      char == '_' ||
      char == '-' ||
      char == '.' ||
      char == ':' ||
      char == '@'
    if !valid {
      return false
    }
  }
  true
}

///|
fn parse_can_log_frame(text : StringView) -> Result[CanFrame, CanLogTextError] {
  match parse_can_frame(text) {
    Ok(frame) => Ok(frame)
    Err(error) => Err(CanLogFrameTextError(error))
  }
}

///|
/// Parse compact SocketCAN text, `INTERFACE ID#DATA`, or the common candump
/// form `(TIMESTAMP) INTERFACE ID#DATA`. Timestamp text is preserved exactly
/// so logs can be correlated without losing decimal precision.
pub fn parse_can_log_record(
  text : StringView,
) -> Result[CanLogRecord, CanLogTextError] {
  let fields = can_log_fields(text)
  match fields {
    [frame_text] => {
      let frame = match parse_can_log_frame(frame_text) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({ timestamp: None, interface_name: None, frame, })
    }
    [interface_name, frame_text] => {
      if parse_can_log_timestamp(interface_name) is Some(_) {
        return Err(CanLogTimestampWithoutInterface)
      }
      if !can_log_interface_is_valid(interface_name) {
        return Err(CanLogInvalidInterface(interface_name))
      }
      let frame = match parse_can_log_frame(frame_text) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({ timestamp: None, interface_name: Some(interface_name), frame, })
    }
    [timestamp_text, interface_name, frame_text] => {
      let timestamp = match parse_can_log_timestamp(timestamp_text) {
        Some(value) => value
        None => return Err(CanLogInvalidTimestamp(timestamp_text))
      }
      if !can_log_interface_is_valid(interface_name) {
        return Err(CanLogInvalidInterface(interface_name))
      }
      let frame = match parse_can_log_frame(frame_text) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({
        timestamp: Some(timestamp),
        interface_name: Some(interface_name),
        frame,
      })
    }
    _ => Err(CanLogInvalidFieldCount(fields.length()))
  }
}

///|
/// Render a log record using the shortest candump form that preserves its
/// timestamp and interface metadata.
pub fn CanLogRecord::to_text(
  self : CanLogRecord,
) -> Result[String, CanLogTextError] {
  let frame_text = match self.frame.to_text() {
    Ok(value) => value
    Err(error) => return Err(CanLogFrameTextError(error))
  }
  match (self.timestamp, self.interface_name) {
    (None, None) => Ok(frame_text)
    (None, Some(interface_name)) =>
      if can_log_interface_is_valid(interface_name) {
        Ok("\{interface_name} \{frame_text}")
      } else {
        Err(CanLogInvalidInterface(interface_name))
      }
    (Some(_), None) => Err(CanLogTimestampWithoutInterface)
    (Some(timestamp), Some(interface_name)) => {
      if !can_log_timestamp_is_valid(timestamp) {
        return Err(CanLogInvalidTimestamp(timestamp))
      }
      if !can_log_interface_is_valid(interface_name) {
        return Err(CanLogInvalidInterface(interface_name))
      }
      Ok("(\{timestamp}) \{interface_name} \{frame_text}")
    }
  }
}
