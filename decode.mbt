///|
/// A raw CAN signal value retains whether the DBC declaration marks it as
/// signed or unsigned.
pub(all) enum RawValue {
  UnsignedRaw(UInt64)
  SignedRaw(Int64)
} derive(Eq, Debug)

///|
pub(all) enum DecodeError {
  UnsupportedByteOrder(ByteOrder)
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
/// Decode the raw bits of an Intel-ordered DBC signal from a CAN payload.
pub fn Signal::decode_raw(
  self : Signal,
  payload : BytesView,
) -> Result[RawValue, DecodeError] {
  if self.byte_order != Intel {
    return Err(UnsupportedByteOrder(self.byte_order))
  }
  if self.start_bit < 0 || self.bit_length < 1 || self.bit_length > 64 {
    return Err(InvalidSignalLayout(self.start_bit, self.bit_length))
  }
  let available_bits = payload.length() * 8
  if self.bit_length > available_bits ||
    self.start_bit > available_bits - self.bit_length {
    return Err(FrameTooShort(self.start_bit + self.bit_length, available_bits))
  }
  let mut raw = 0UL
  for offset = 0; offset < self.bit_length; offset = offset + 1 {
    let absolute_bit = self.start_bit + offset
    let byte = payload[absolute_bit / 8].to_uint64()
    let bit = (byte >> (absolute_bit % 8)) & 1UL
    raw = raw | (bit << offset)
  }
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

///|
/// Decode an Intel-ordered DBC signal and apply its factor and offset.
pub fn Signal::decode(
  self : Signal,
  payload : BytesView,
) -> Result[Double, DecodeError] {
  match self.decode_raw(payload) {
    Ok(raw) => Ok(raw.to_double() * self.factor + self.offset)
    Err(error) => Err(error)
  }
}
