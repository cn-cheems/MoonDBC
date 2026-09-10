///|
/// A raw CAN signal value retains whether the DBC declaration marks it as
/// signed or unsigned.
pub(all) enum RawValue {
  UnsignedRaw(UInt64)
  SignedRaw(Int64)
} derive(Eq, Debug)

///|
pub(all) enum DecodeError {
  InvalidSignalLayout(Int, Int)
  FrameTooShort(Int, Int)
} derive(Eq, Debug)

///|
pub fn RawValue::to_double(self : RawValue) -> Double {
  match self {
    UnsignedRaw(value) => value.to_double()
    SignedRaw(value) => value.to_double()
  }
}

///|
fn decode_intel_bits(
  payload : BytesView,
  start_bit : Int,
  bit_length : Int,
) -> Result[UInt64, DecodeError] {
  let available_bits = payload.length() * 8
  if bit_length > available_bits || start_bit > available_bits - bit_length {
    return Err(FrameTooShort(start_bit + bit_length, available_bits))
  }
  let mut raw = 0UL
  for offset = 0; offset < bit_length; offset = offset + 1 {
    let absolute_bit = start_bit + offset
    let byte = payload[absolute_bit / 8].to_uint64()
    let bit = (byte >> (absolute_bit % 8)) & 1UL
    raw = raw | (bit << offset)
  }
  Ok(raw)
}

///|
fn decode_motorola_bits(
  payload : BytesView,
  start_bit : Int,
  bit_length : Int,
) -> Result[UInt64, DecodeError] {
  let available_bits = payload.length() * 8
  let mut absolute_bit = start_bit
  let mut raw = 0UL
  for offset = 0; offset < bit_length; offset = offset + 1 {
    if absolute_bit >= available_bits {
      return Err(FrameTooShort(absolute_bit + 1, available_bits))
    }
    let byte = payload[absolute_bit / 8].to_uint64()
    let bit = (byte >> (absolute_bit % 8)) & 1UL
    raw = (raw << 1) | bit
    if offset + 1 < bit_length {
      absolute_bit = if absolute_bit % 8 == 0 {
        absolute_bit + 15
      } else {
        absolute_bit - 1
      }
    }
  }
  Ok(raw)
}

///|
/// Decode the raw bits of an Intel- or Motorola-ordered DBC signal.
pub fn Signal::decode_raw(
  self : Signal,
  payload : BytesView,
) -> Result[RawValue, DecodeError] {
  if self.start_bit < 0 || self.bit_length < 1 || self.bit_length > 64 {
    return Err(InvalidSignalLayout(self.start_bit, self.bit_length))
  }
  let raw_result = match self.byte_order {
    Intel => decode_intel_bits(payload, self.start_bit, self.bit_length)
    Motorola => decode_motorola_bits(payload, self.start_bit, self.bit_length)
  }
  match raw_result {
    Err(error) => Err(error)
    Ok(raw) =>
      match self.value_kind {
        Unsigned => Ok(UnsignedRaw(raw))
        Signed => {
          if self.bit_length == 64 {
            return Ok(SignedRaw(raw.reinterpret_as_int64()))
          }
          let sign_bit = 1UL << (self.bit_length - 1)
          let signed_bits = if (raw & sign_bit) != 0UL {
            raw | (0UL.lnot() << self.bit_length)
          } else {
            raw
          }
          Ok(SignedRaw(signed_bits.reinterpret_as_int64()))
        }
      }
  }
}

///|
/// Decode a DBC signal and apply its factor and offset.
pub fn Signal::decode(
  self : Signal,
  payload : BytesView,
) -> Result[Double, DecodeError] {
  match self.decode_raw(payload) {
    Ok(raw) => Ok(raw.to_double() * self.factor + self.offset)
    Err(error) => Err(error)
  }
}
