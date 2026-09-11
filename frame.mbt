///|
pub(all) struct DecodedSignal {
  name : String
  raw : RawValue
  physical : Double
  unit : String
  label : String?
} derive(Eq, Debug)

///|
pub(all) struct DecodedMessage {
  id : UInt
  name : String
  signals : Array[DecodedSignal]
} derive(Eq, Debug)

///|
pub(all) enum FrameDecodeError {
  UnknownMessage(UInt)
  PayloadTooShort(Int, Int)
  MissingMultiplexer
  MultipleMultiplexers
  SignalDecodeFailed(String, DecodeError)
} derive(Eq, Debug)

///|
fn decode_signal(
  signal : Signal,
  payload : BytesView,
) -> Result[DecodedSignal, FrameDecodeError] {
  match signal.decode_raw(payload) {
    Err(error) => Err(SignalDecodeFailed(signal.name, error))
    Ok(raw) =>
      Ok({
        name: signal.name,
        raw,
        physical: raw.to_double() * signal.factor + signal.offset,
        unit: signal.unit,
        label: None,
      })
  }
}

///|
fn selector_matches(raw : RawValue, selector : Int) -> Bool {
  match raw {
    UnsignedRaw(value) => value == selector.to_uint64()
    SignedRaw(value) => value == selector.to_int64()
  }
}

///|
/// Decode every active signal in a CAN frame. Multiplexed signals are emitted
/// only when their selector matches the decoded multiplexer value.
pub fn Message::decode_frame(
  self : Message,
  payload : BytesView,
) -> Result[DecodedMessage, FrameDecodeError] {
  if payload.length() < self.payload_size {
    return Err(PayloadTooShort(self.payload_size, payload.length()))
  }
  let mut multiplexer : Signal? = None
  let mut has_multiplexed_signal = false
  for signal in self.signals {
    match signal.multiplex {
      Plain => ()
      Multiplexed(_) => has_multiplexed_signal = true
      Multiplexer =>
        match multiplexer {
          Some(_) => return Err(MultipleMultiplexers)
          None => multiplexer = Some(signal)
        }
    }
  }
  if has_multiplexed_signal && multiplexer is None {
    return Err(MissingMultiplexer)
  }
  let decoded_multiplexer = match multiplexer {
    None => None
    Some(signal) =>
      match decode_signal(signal, payload) {
        Ok(decoded) => Some(decoded)
        Err(error) => return Err(error)
      }
  }
  let signals : Array[DecodedSignal] = []
  for signal in self.signals {
    match signal.multiplex {
      Plain =>
        match decode_signal(signal, payload) {
          Ok(decoded) => signals.push(decoded)
          Err(error) => return Err(error)
        }
      Multiplexer =>
        match decoded_multiplexer {
          Some(decoded) => signals.push(decoded)
          None => ()
        }
      Multiplexed(selector) =>
        match decoded_multiplexer {
          Some(decoded) if selector_matches(decoded.raw, selector) =>
            match decode_signal(signal, payload) {
              Ok(value) => signals.push(value)
              Err(error) => return Err(error)
            }
          _ => ()
        }
    }
  }
  Ok({ id: self.id, name: self.name, signals, })
}

///|
fn raw_value_as_int64(raw : RawValue) -> Int64? {
  match raw {
    SignedRaw(value) => Some(value)
    UnsignedRaw(value) =>
      if value <= 9223372036854775807UL {
        Some(value.reinterpret_as_int64())
      } else {
        None
      }
  }
}

///|
/// Find and decode a message, enriching decoded signals with `VAL_` labels.
pub fn Database::decode_frame(
  self : Database,
  message_id : UInt,
  payload : BytesView,
) -> Result[DecodedMessage, FrameDecodeError] {
  let message = match self.find_message(message_id) {
    Some(message) => message
    None => return Err(UnknownMessage(message_id))
  }
  match message.decode_frame(payload) {
    Err(error) => Err(error)
    Ok(decoded) => {
      let signals : Array[DecodedSignal] = []
      for signal in decoded.signals {
        let label = match raw_value_as_int64(signal.raw) {
          Some(value) => self.value_label(message_id, signal.name, value)
          None => None
        }
        signals.push({
          name: signal.name,
          raw: signal.raw,
          physical: signal.physical,
          unit: signal.unit,
          label,
        })
      }
      Ok({ id: decoded.id, name: decoded.name, signals, })
    }
  }
}
