///|
pub(all) enum EncodeError {
  EncodeInvalidLayout(Int, Int)
  EncodeFrameTooShort(Int, Int)
  ValueKindMismatch(ValueKind, RawValue)
  SignalValueTypeMismatch(SignalValueType, RawValue)
  RawValueOutOfRange(RawValue, Int)
  InvalidFactor(Double)
  NonFinitePhysicalValue(Double)
  PhysicalValueOutOfRange(Double, Double, Double)
  PhysicalRawOutOfRange(Double, Int)
} derive(Eq, Debug)

///|
fn unsigned_max(bit_length : Int) -> UInt64 {
  if bit_length == 64 {
    0UL.lnot()
  } else {
    (1UL << bit_length) - 1UL
  }
}

///|
fn raw_bits_for_signal(
  signal : Signal,
  value : RawValue,
) -> Result[UInt64, EncodeError] {
  match signal.value_type {
    Float32 =>
      match value {
        FloatRaw(raw) =>
          Ok(Float::from_double(raw).reinterpret_as_uint().to_uint64())
        _ => Err(SignalValueTypeMismatch(Float32, value))
      }
    Float64 =>
      match value {
        FloatRaw(raw) => Ok(raw.reinterpret_as_uint64())
        _ => Err(SignalValueTypeMismatch(Float64, value))
      }
    Integer =>
      match (signal.value_kind, value) {
        (Unsigned, UnsignedRaw(raw)) =>
          if raw > unsigned_max(signal.bit_length) {
            Err(RawValueOutOfRange(value, signal.bit_length))
          } else {
            Ok(raw)
          }
        (Signed, SignedRaw(raw)) => {
          if signal.bit_length < 64 {
            let limit = 1L << (signal.bit_length - 1)
            if raw < -limit || raw >= limit {
              return Err(RawValueOutOfRange(value, signal.bit_length))
            }
          }
          Ok(raw.reinterpret_as_uint64() & unsigned_max(signal.bit_length))
        }
        _ => Err(ValueKindMismatch(signal.value_kind, value))
      }
  }
}

///|
fn set_payload_bit(
  payload : Array[Byte],
  absolute_bit : Int,
  bit : UInt64,
) -> Unit {
  let byte_index = absolute_bit / 8
  let bit_mask = 1UL << (absolute_bit % 8)
  let byte = payload[byte_index].to_uint64()
  let updated = if bit == 0UL {
    byte & bit_mask.lnot()
  } else {
    byte | bit_mask
  }
  payload[byte_index] = updated.to_byte()
}

///|
fn validate_encode_layout(
  signal : Signal,
  payload : BytesView,
) -> Result[Unit, EncodeError] {
  if signal.start_bit < 0 || signal.bit_length < 1 || signal.bit_length > 64 {
    return Err(EncodeInvalidLayout(signal.start_bit, signal.bit_length))
  }
  match signal.value_type {
    Float32 if signal.bit_length != 32 =>
      return Err(EncodeInvalidLayout(signal.start_bit, signal.bit_length))
    Float64 if signal.bit_length != 64 =>
      return Err(EncodeInvalidLayout(signal.start_bit, signal.bit_length))
    _ => ()
  }
  let available_bits = payload.length() * 8
  match signal.byte_order {
    Intel =>
      if signal.bit_length > available_bits ||
        signal.start_bit > available_bits - signal.bit_length {
        Err(
          EncodeFrameTooShort(
            signal.start_bit + signal.bit_length,
            available_bits,
          ),
        )
      } else {
        Ok(())
      }
    Motorola => {
      let mut absolute_bit = signal.start_bit
      for offset = 0; offset < signal.bit_length; offset = offset + 1 {
        if absolute_bit >= available_bits {
          return Err(EncodeFrameTooShort(absolute_bit + 1, available_bits))
        }
        if offset + 1 < signal.bit_length {
          absolute_bit = if absolute_bit % 8 == 0 {
            absolute_bit + 15
          } else {
            absolute_bit - 1
          }
        }
      }
      Ok(())
    }
  }
}

///|
/// Insert a raw signal value into a copy of a CAN payload.
pub fn Signal::encode_raw(
  self : Signal,
  payload : BytesView,
  value : RawValue,
) -> Result[Bytes, EncodeError] {
  match validate_encode_layout(self, payload) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let raw = match raw_bits_for_signal(self, value) {
    Err(error) => return Err(error)
    Ok(raw) => raw
  }
  let output = payload.to_array()
  match self.byte_order {
    Intel =>
      for offset = 0; offset < self.bit_length; offset = offset + 1 {
        set_payload_bit(output, self.start_bit + offset, (raw >> offset) & 1UL)
      }
    Motorola => {
      let mut absolute_bit = self.start_bit
      for offset = 0; offset < self.bit_length; offset = offset + 1 {
        let raw_offset = self.bit_length - 1 - offset
        set_payload_bit(output, absolute_bit, (raw >> raw_offset) & 1UL)
        if offset + 1 < self.bit_length {
          absolute_bit = if absolute_bit % 8 == 0 {
            absolute_bit + 15
          } else {
            absolute_bit - 1
          }
        }
      }
    }
  }
  Ok(Bytes::from_array(output))
}

///|
/// Convert a physical value to the nearest raw integer and insert it into a
/// copy of a CAN payload.
pub fn Signal::encode(
  self : Signal,
  payload : BytesView,
  physical : Double,
) -> Result[Bytes, EncodeError] {
  match validate_encode_layout(self, payload) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if self.factor == 0.0 || self.factor.is_nan() || self.factor.is_inf() {
    return Err(InvalidFactor(self.factor))
  }
  if physical.is_nan() || physical.is_inf() {
    return Err(NonFinitePhysicalValue(physical))
  }
  if physical < self.minimum || physical > self.maximum {
    return Err(PhysicalValueOutOfRange(physical, self.minimum, self.maximum))
  }
  let unscaled = (physical - self.offset) / self.factor
  match self.value_type {
    Float32 => {
      let raw = Float::from_double(unscaled).to_double()
      if raw.is_nan() || raw.is_inf() {
        return Err(PhysicalRawOutOfRange(unscaled, self.bit_length))
      }
      self.encode_raw(payload, FloatRaw(raw))
    }
    Float64 => {
      if unscaled.is_nan() || unscaled.is_inf() {
        return Err(PhysicalRawOutOfRange(unscaled, self.bit_length))
      }
      self.encode_raw(payload, FloatRaw(unscaled))
    }
    Integer => {
      let raw = unscaled.round()
      match self.value_kind {
        Unsigned => {
          let maximum = unsigned_max(self.bit_length).to_double()
          let too_large = if self.bit_length == 64 {
            raw >= maximum
          } else {
            raw > maximum
          }
          if raw < 0.0 || too_large {
            return Err(PhysicalRawOutOfRange(raw, self.bit_length))
          }
          self.encode_raw(payload, UnsignedRaw(raw.to_uint64()))
        }
        Signed => {
          let limit = if self.bit_length == 64 {
            9223372036854775808.0
          } else {
            let limit = (1L << (self.bit_length - 1)).to_double()
            limit
          }
          if raw < -limit || raw >= limit {
            return Err(PhysicalRawOutOfRange(raw, self.bit_length))
          }
          self.encode_raw(payload, SignedRaw(raw.to_int64()))
        }
      }
    }
  }
}
