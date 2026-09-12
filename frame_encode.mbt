///|
/// A physical value assigned to a signal when building a complete CAN frame.
pub(all) struct SignalAssignment {
  name : String
  physical : Double
} derive(Eq, Debug)

///|
pub(all) enum FrameEncodeError {
  FrameEncodeUnknownMessage(UInt)
  FrameEncodeInvalidCanIdentifier(UInt, Bool)
  FrameEncodeUnknownCanMessage(UInt, Bool)
  FrameEncodeInvalidPayloadSize(Int)
  FrameEncodeUnknownSignal(String)
  FrameEncodeDuplicateSignal(String)
  FrameEncodeMissingSignal(String)
  FrameEncodeInactiveSignal(String, Int)
  FrameEncodeMissingMultiplexer
  FrameEncodeMultipleMultiplexers
  FrameSignalEncodeFailed(String, EncodeError)
  FrameMultiplexerDecodeFailed(String, DecodeError)
} derive(Eq, Debug)

///|
fn find_assignment(
  assignments : Array[SignalAssignment],
  name : StringView,
) -> SignalAssignment? {
  for assignment in assignments {
    if assignment.name.view() == name {
      return Some(assignment)
    }
  }
  None
}

///|
fn validate_assignments(
  message : Message,
  assignments : Array[SignalAssignment],
) -> Result[Unit, FrameEncodeError] {
  for index, assignment in assignments {
    if message.find_signal(assignment.name) is None {
      return Err(FrameEncodeUnknownSignal(assignment.name))
    }
    for previous = 0; previous < index; previous = previous + 1 {
      if assignments[previous].name == assignment.name {
        return Err(FrameEncodeDuplicateSignal(assignment.name))
      }
    }
  }
  Ok(())
}

///|
fn encode_multiplexer_layout(
  message : Message,
) -> Result[Signal?, FrameEncodeError] {
  let mut multiplexer : Signal? = None
  let mut has_multiplexed_signal = false
  for signal in message.signals {
    match signal.multiplex {
      Plain => ()
      Multiplexed(_) => has_multiplexed_signal = true
      Multiplexer =>
        match multiplexer {
          None => multiplexer = Some(signal)
          Some(_) => return Err(FrameEncodeMultipleMultiplexers)
        }
    }
  }
  if has_multiplexed_signal && multiplexer is None {
    Err(FrameEncodeMissingMultiplexer)
  } else {
    Ok(multiplexer)
  }
}

///|
fn encode_assigned_signal(
  signal : Signal,
  assignment : SignalAssignment,
  payload : BytesView,
) -> Result[Bytes, FrameEncodeError] {
  match signal.encode(payload, assignment.physical) {
    Ok(encoded) => Ok(encoded)
    Err(error) => Err(FrameSignalEncodeFailed(signal.name, error))
  }
}

///|
fn require_assignment(
  signal : Signal,
  assignments : Array[SignalAssignment],
) -> Result[SignalAssignment, FrameEncodeError] {
  match find_assignment(assignments, signal.name) {
    Some(assignment) => Ok(assignment)
    None => Err(FrameEncodeMissingSignal(signal.name))
  }
}

///|
/// Build a zero-initialized CAN payload from named physical signal values.
/// Plain signals and the selected multiplex branch must be assigned exactly
/// once. Assignments for inactive multiplex branches are rejected.
pub fn Message::encode_frame(
  self : Message,
  assignments : Array[SignalAssignment],
) -> Result[Bytes, FrameEncodeError] {
  if self.payload_size < 0 {
    return Err(FrameEncodeInvalidPayloadSize(self.payload_size))
  }
  match validate_assignments(self, assignments) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let multiplexer = match encode_multiplexer_layout(self) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let mut payload = Bytes::make(self.payload_size, b'\x00')
  let selector = match multiplexer {
    None => None
    Some(signal) => {
      let assignment = match require_assignment(signal, assignments) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      payload = match encode_assigned_signal(signal, assignment, payload) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match signal.decode_raw(payload) {
        Ok(raw) => Some(raw)
        Err(error) =>
          return Err(FrameMultiplexerDecodeFailed(signal.name, error))
      }
    }
  }
  for signal in self.signals {
    match signal.multiplex {
      Multiplexer => ()
      Plain => {
        let assignment = match require_assignment(signal, assignments) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        payload = match encode_assigned_signal(signal, assignment, payload) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
      }
      Multiplexed(expected) => {
        let active = match selector {
          Some(raw) => selector_matches(raw, expected)
          None => false
        }
        match (active, find_assignment(assignments, signal.name)) {
          (true, Some(assignment)) =>
            payload = match
              encode_assigned_signal(signal, assignment, payload) {
              Err(error) => return Err(error)
              Ok(value) => value
            }
          (true, None) => return Err(FrameEncodeMissingSignal(signal.name))
          (false, Some(_)) =>
            return Err(FrameEncodeInactiveSignal(signal.name, expected))
          (false, None) => ()
        }
      }
    }
  }
  Ok(payload)
}

///|
/// Find a message by its DBC declaration identifier and build its CAN payload.
/// Use `encode_can_frame` when starting from a bus arbitration identifier.
pub fn Database::encode_frame(
  self : Database,
  message_id : UInt,
  assignments : Array[SignalAssignment],
) -> Result[Bytes, FrameEncodeError] {
  match self.find_message(message_id) {
    None => Err(FrameEncodeUnknownMessage(message_id))
    Some(message) => message.encode_frame(assignments)
  }
}

///|
/// Build a complete standard or extended CAN frame from named physical values.
pub fn Database::encode_can_frame(
  self : Database,
  frame_id : UInt,
  is_extended_frame : Bool,
  assignments : Array[SignalAssignment],
) -> Result[CanFrame, FrameEncodeError] {
  let dbc_id = match dbc_message_id_from_frame(frame_id, is_extended_frame) {
    Some(value) => value
    None =>
      return Err(FrameEncodeInvalidCanIdentifier(frame_id, is_extended_frame))
  }
  let message = match self.find_message(dbc_id) {
    Some(value) => value
    None =>
      return Err(FrameEncodeUnknownCanMessage(frame_id, is_extended_frame))
  }
  let payload = match message.encode_frame(assignments) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ id: frame_id, is_extended_frame, payload, })
}
