///|
pub(all) enum ValidationIssue {
  DuplicateMessageIdIssue(UInt)
  InvalidPayloadSizeIssue(UInt, Int)
  DuplicateSignalNameIssue(UInt, String)
  InvalidSignalLayoutIssue(UInt, String, Int, Int)
  SignalOutsidePayloadIssue(UInt, String)
  InvalidScaleIssue(UInt, String, Double, Double)
  InvalidPhysicalRangeIssue(UInt, String, Double, Double)
  MultipleMultiplexersIssue(UInt)
  MissingMultiplexerIssue(UInt, String)
  MultiplexSelectorOutOfRangeIssue(UInt, String, Int)
  OverlappingSignalsIssue(UInt, String, String)
} derive(Eq, Debug)

///|
fn signal_bits(signal : Signal, available_bits : Int) -> Array[Int]? {
  if signal.start_bit < 0 || signal.bit_length < 1 || signal.bit_length > 64 {
    return None
  }
  let bits : Array[Int] = []
  match signal.byte_order {
    Intel => {
      if signal.bit_length > available_bits ||
        signal.start_bit > available_bits - signal.bit_length {
        return None
      }
      for offset = 0; offset < signal.bit_length; offset = offset + 1 {
        bits.push(signal.start_bit + offset)
      }
    }
    Motorola => {
      let mut absolute_bit = signal.start_bit
      for offset = 0; offset < signal.bit_length; offset = offset + 1 {
        if absolute_bit >= available_bits {
          return None
        }
        bits.push(absolute_bit)
        if offset + 1 < signal.bit_length {
          absolute_bit = if absolute_bit % 8 == 0 {
            absolute_bit + 15
          } else {
            absolute_bit - 1
          }
        }
      }
    }
  }
  Some(bits)
}

///|
fn signals_can_coexist(left : MultiplexRole, right : MultiplexRole) -> Bool {
  match (left, right) {
    (Multiplexed(left_selector), Multiplexed(right_selector)) =>
      left_selector == right_selector
    _ => true
  }
}

///|
fn share_occupied_bit(left : Array[Int], right : Array[Int]) -> Bool {
  for left_bit in left {
    for right_bit in right {
      if left_bit == right_bit {
        return true
      }
    }
  }
  false
}

///|
fn multiplex_selector_fits(signal : Signal, selector : Int) -> Bool {
  if selector < 0 || signal.bit_length < 1 || signal.bit_length > 64 {
    return false
  }
  match signal.value_kind {
    Unsigned =>
      if signal.bit_length == 64 {
        true
      } else {
        selector.to_uint64() <= (1UL << signal.bit_length) - 1UL
      }
    Signed =>
      if signal.bit_length == 64 {
        true
      } else {
        selector.to_int64() < 1L << (signal.bit_length - 1)
      }
  }
}

///|
fn validate_message(message : Message, issues : Array[ValidationIssue]) -> Unit {
  if message.payload_size < 0 || message.payload_size > 64 {
    issues.push(InvalidPayloadSizeIssue(message.id, message.payload_size))
  }
  let available_bits = if message.payload_size >= 0 &&
    message.payload_size <= 64 {
    message.payload_size * 8
  } else {
    0
  }
  let occupied : Array[Array[Int]?] = []
  let mut multiplexer : Signal? = None
  let mut multiplexer_count = 0
  for index, signal in message.signals {
    for previous = 0; previous < index; previous = previous + 1 {
      if message.signals[previous].name == signal.name {
        issues.push(DuplicateSignalNameIssue(message.id, signal.name))
      }
    }
    let layout_valid = signal.start_bit >= 0 &&
      signal.bit_length >= 1 &&
      signal.bit_length <= 64
    if !layout_valid {
      issues.push(
        InvalidSignalLayoutIssue(
          message.id,
          signal.name,
          signal.start_bit,
          signal.bit_length,
        ),
      )
      occupied.push(None)
    } else {
      let bits = signal_bits(signal, available_bits)
      if bits is None {
        issues.push(SignalOutsidePayloadIssue(message.id, signal.name))
      }
      occupied.push(bits)
    }
    if signal.factor == 0.0 ||
      signal.factor.is_nan() ||
      signal.factor.is_inf() ||
      signal.offset.is_nan() ||
      signal.offset.is_inf() {
      issues.push(
        InvalidScaleIssue(message.id, signal.name, signal.factor, signal.offset),
      )
    }
    if signal.minimum.is_nan() ||
      signal.minimum.is_inf() ||
      signal.maximum.is_nan() ||
      signal.maximum.is_inf() ||
      signal.minimum > signal.maximum {
      issues.push(
        InvalidPhysicalRangeIssue(
          message.id,
          signal.name,
          signal.minimum,
          signal.maximum,
        ),
      )
    }
    match signal.multiplex {
      Multiplexer => {
        multiplexer_count += 1
        if multiplexer is None {
          multiplexer = Some(signal)
        }
      }
      _ => ()
    }
  }
  if multiplexer_count > 1 {
    issues.push(MultipleMultiplexersIssue(message.id))
  }
  for signal in message.signals {
    match signal.multiplex {
      Multiplexed(selector) =>
        match multiplexer {
          None => issues.push(MissingMultiplexerIssue(message.id, signal.name))
          Some(mux) =>
            if multiplexer_count == 1 && !multiplex_selector_fits(mux, selector) {
              issues.push(
                MultiplexSelectorOutOfRangeIssue(
                  message.id,
                  signal.name,
                  selector,
                ),
              )
            }
        }
      _ => ()
    }
  }
  for right = 0; right < message.signals.length(); right = right + 1 {
    for left = 0; left < right; left = left + 1 {
      if signals_can_coexist(
          message.signals[left].multiplex,
          message.signals[right].multiplex,
        ) {
        match (occupied[left], occupied[right]) {
          (Some(left_bits), Some(right_bits)) =>
            if share_occupied_bit(left_bits, right_bits) {
              issues.push(
                OverlappingSignalsIssue(
                  message.id,
                  message.signals[left].name,
                  message.signals[right].name,
                ),
              )
            }
          _ => ()
        }
      }
    }
  }
}

///|
/// Validate cross-field and bit-layout constraints that are not syntax errors.
pub fn Database::validate(self : Database) -> Array[ValidationIssue] {
  let issues : Array[ValidationIssue] = []
  for index, message in self.messages {
    for previous = 0; previous < index; previous = previous + 1 {
      if self.messages[previous].id == message.id {
        issues.push(DuplicateMessageIdIssue(message.id))
      }
    }
    validate_message(message, issues)
  }
  issues
}
