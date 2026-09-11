///|
/// A compact CAN frame with optional candump timestamp and interface metadata.
pub(all) struct CanLogRecord {
  timestamp : String?
  interface_name : String?
  /// `None` denotes Classical CAN; `Some(flags)` denotes CAN FD.
  fd_flags : Byte?
  frame : CanFrame
} derive(Eq, Debug)

///|
pub(all) enum CanLogTextError {
  CanLogInvalidFieldCount(Int)
  CanLogInvalidTimestamp(String)
  CanLogInvalidInterface(String)
  CanLogMissingFdFlags
  CanLogInvalidFdFlags(String)
  CanLogFdFlagsOutOfRange(Int)
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
fn parse_can_log_frame(
  text : StringView,
) -> Result[(CanFrame, Byte?), CanLogTextError] {
  match text.find("##") {
    None =>
      match parse_can_frame(text) {
        Ok(frame) => Ok((frame, None))
        Err(error) => Err(CanLogFrameTextError(error))
      }
    Some(separator) => {
      let flags_start = separator + 2
      if flags_start >= text.length() {
        return Err(CanLogMissingFdFlags)
      }
      let flags_text = text[flags_start:flags_start + 1]
      let mut flags : Int? = None
      for char in flags_text.iter() {
        flags = can_hex_nibble(char)
      }
      let flags = match flags {
        Some(value) => value.to_byte()
        None => return Err(CanLogInvalidFdFlags(flags_text.to_owned()))
      }
      let classical_text = "\{text[:separator]}#\{text[flags_start + 1:]}"
      match parse_can_frame(classical_text) {
        Ok(frame) => Ok((frame, Some(flags)))
        Err(error) => Err(CanLogFrameTextError(error))
      }
    }
  }
}

///|
fn can_log_frame_to_text(
  frame : CanFrame,
  fd_flags : Byte?,
) -> Result[String, CanLogTextError] {
  let frame_text = match frame.to_text() {
    Ok(value) => value
    Err(error) => return Err(CanLogFrameTextError(error))
  }
  match fd_flags {
    None => Ok(frame_text)
    Some(flags) => {
      let value = flags.to_int()
      if value > 0xF {
        return Err(CanLogFdFlagsOutOfRange(value))
      }
      let separator = frame_text.find("#").unwrap()
      Ok(
        "\{frame_text[:separator]}##\{can_hex_digit(value)}\{frame_text[separator + 1:]}",
      )
    }
  }
}

///|
/// Parse compact SocketCAN text, `INTERFACE ID#DATA`, or the common candump
/// form `(TIMESTAMP) INTERFACE ID#DATA`. CAN FD uses `ID##FLAGS+DATA` with one
/// hexadecimal flags digit. Timestamp text is preserved without losing precision.
pub fn parse_can_log_record(
  text : StringView,
) -> Result[CanLogRecord, CanLogTextError] {
  let fields = can_log_fields(text)
  match fields {
    [frame_text] => {
      let (frame, fd_flags) = match parse_can_log_frame(frame_text) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({ timestamp: None, interface_name: None, fd_flags, frame, })
    }
    [interface_name, frame_text] => {
      if parse_can_log_timestamp(interface_name) is Some(_) {
        return Err(CanLogTimestampWithoutInterface)
      }
      if !can_log_interface_is_valid(interface_name) {
        return Err(CanLogInvalidInterface(interface_name))
      }
      let (frame, fd_flags) = match parse_can_log_frame(frame_text) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({
        timestamp: None,
        interface_name: Some(interface_name),
        fd_flags,
        frame,
      })
    }
    [timestamp_text, interface_name, frame_text] => {
      let timestamp = match parse_can_log_timestamp(timestamp_text) {
        Some(value) => value
        None => return Err(CanLogInvalidTimestamp(timestamp_text))
      }
      if !can_log_interface_is_valid(interface_name) {
        return Err(CanLogInvalidInterface(interface_name))
      }
      let (frame, fd_flags) = match parse_can_log_frame(frame_text) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok({
        timestamp: Some(timestamp),
        interface_name: Some(interface_name),
        fd_flags,
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
  let frame_text = match can_log_frame_to_text(self.frame, self.fd_flags) {
    Ok(value) => value
    Err(error) => return Err(error)
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
