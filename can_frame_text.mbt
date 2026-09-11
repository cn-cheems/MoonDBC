///|
/// A CAN data frame independent of a specific socket or operating system.
pub(all) struct CanFrame {
  id : UInt
  payload : Bytes
} derive(Eq, Debug)

///|
pub(all) enum CanFrameTextError {
  CanFrameMissingSeparator
  CanFrameEmptyIdentifier
  CanFrameIdentifierTooLong(Int)
  CanFrameInvalidIdentifier(Int, Char)
  CanFrameIdentifierOutOfRange(UInt)
  CanFrameOddPayloadLength(Int)
  CanFramePayloadTooLong(Int)
  CanFrameInvalidPayload(Int, Char)
} derive(Eq, Debug)

///|
fn can_hex_nibble(char : Char) -> Int? {
  if char >= '0' && char <= '9' {
    Some(char.to_int() - '0'.to_int())
  } else if char >= 'a' && char <= 'f' {
    Some(char.to_int() - 'a'.to_int() + 10)
  } else if char >= 'A' && char <= 'F' {
    Some(char.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn parse_can_identifier(text : StringView) -> Result[UInt, CanFrameTextError] {
  if text.is_empty() {
    return Err(CanFrameEmptyIdentifier)
  }
  if text.length() > 8 {
    return Err(CanFrameIdentifierTooLong(text.length()))
  }
  let mut identifier = 0U
  let mut index = 0
  for char in text.iter() {
    let nibble = match can_hex_nibble(char) {
      Some(value) => value
      None => return Err(CanFrameInvalidIdentifier(index, char))
    }
    identifier = identifier * 16U + nibble.reinterpret_as_uint()
    index += 1
  }
  if identifier > 0x1FFFFFFFU {
    Err(CanFrameIdentifierOutOfRange(identifier))
  } else {
    Ok(identifier)
  }
}

///|
fn parse_can_payload(text : StringView) -> Result[Bytes, CanFrameTextError] {
  if text.length() % 2 != 0 {
    return Err(CanFrameOddPayloadLength(text.length()))
  }
  let payload_length = text.length() / 2
  if payload_length > 64 {
    return Err(CanFramePayloadTooLong(payload_length))
  }
  let payload : Array[Byte] = []
  let mut high_nibble : Int? = None
  let mut index = 0
  for char in text.iter() {
    let nibble = match can_hex_nibble(char) {
      Some(value) => value
      None => return Err(CanFrameInvalidPayload(index, char))
    }
    match high_nibble {
      None => high_nibble = Some(nibble)
      Some(high) => {
        payload.push((high * 16 + nibble).to_byte())
        high_nibble = None
      }
    }
    index += 1
  }
  Ok(Bytes::from_array(payload))
}

///|
/// Parse the compact SocketCAN representation `ID#DATA`. Both fields use
/// hexadecimal notation; the payload may be empty and may contain up to 64
/// bytes for CAN FD compatibility.
pub fn parse_can_frame(
  text : StringView,
) -> Result[CanFrame, CanFrameTextError] {
  let input = text.trim()
  let separator = match input.find("#") {
    Some(index) => index
    None => return Err(CanFrameMissingSeparator)
  }
  let identifier = match parse_can_identifier(input[:separator]) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let payload = match parse_can_payload(input[separator + 1:]) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ id: identifier, payload, })
}

///|
fn append_padded_identifier(chars : Array[Char], identifier : UInt) -> Unit {
  let text = identifier.to_string(radix=16).to_upper()
  let width = if identifier <= 0x7FFU { 3 } else { 8 }
  for padding = text.length(); padding < width; padding = padding + 1 {
    chars.push('0')
  }
  for char in text.iter() {
    chars.push(char)
  }
}

///|
fn can_hex_digit(value : Int) -> Char {
  if value < 10 {
    (value + '0'.to_int()).to_char().unwrap()
  } else {
    (value - 10 + 'A'.to_int()).to_char().unwrap()
  }
}

///|
/// Render a frame as canonical compact SocketCAN text. Standard identifiers
/// use three hexadecimal digits and extended identifiers use eight.
pub fn CanFrame::to_text(self : CanFrame) -> Result[String, CanFrameTextError] {
  if self.id > 0x1FFFFFFFU {
    return Err(CanFrameIdentifierOutOfRange(self.id))
  }
  if self.payload.length() > 64 {
    return Err(CanFramePayloadTooLong(self.payload.length()))
  }
  let chars : Array[Char] = []
  append_padded_identifier(chars, self.id)
  chars.push('#')
  for byte in self.payload {
    let value = byte.to_int()
    chars.push(can_hex_digit(value >> 4))
    chars.push(can_hex_digit(value & 0xF))
  }
  Ok(String::from_array(chars))
}

///|
/// Decode a parsed CAN frame using the message identifier in the frame.
pub fn Database::decode_can_frame(
  self : Database,
  frame : CanFrame,
) -> Result[DecodedMessage, FrameDecodeError] {
  self.decode_frame(frame.id, frame.payload)
}
