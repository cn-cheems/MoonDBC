///|
pub(all) enum ValidationIssue {
  InvalidMessageIdentifierIssue(UInt)
  DuplicateMessageIdIssue(UInt)
  InvalidPayloadSizeIssue(UInt, Int)
  DuplicateSignalNameIssue(UInt, String)
  InvalidSignalLayoutIssue(UInt, String, Int, Int)
  InvalidSignalValueTypeIssue(UInt, String, SignalValueType, Int)
  FloatingMultiplexerIssue(UInt, String, SignalValueType)
  SignalOutsidePayloadIssue(UInt, String)
  InvalidScaleIssue(UInt, String, Double, Double)
  InvalidPhysicalRangeIssue(UInt, String, Double, Double)
  MultipleMultiplexersIssue(UInt)
  MissingMultiplexerIssue(UInt, String)
  MultiplexSelectorOutOfRangeIssue(UInt, String, Int)
  InvalidMultiplexRangeIssue(UInt, String, Int, Int)
  UnknownMultiplexSelectorIssue(UInt, String, String)
  OverlappingSignalsIssue(UInt, String, String)
  DuplicateCommentIssue(DbcCommentTarget)
  UnknownCommentNodeIssue(String)
  UnknownCommentMessageIssue(UInt)
  UnknownCommentSignalIssue(UInt, String)
  DuplicateMessageTransmitterIssue(UInt, String)
  DuplicateAttributeDefinitionIssue(String)
  DuplicateAttributeDefaultIssue(String)
  DuplicateAttributeAssignmentIssue(String, DbcAttributeTarget)
  UnknownAttributeDefinitionIssue(String)
  InvalidAttributeTargetIssue(String, DbcAttributeTarget)
  AttributeScopeMismatchIssue(String, DbcAttributeTarget)
  InvalidAttributeValueIssue(String)
  DuplicateSignalGroupIssue(UInt, String)
  InvalidSignalGroupIssue(UInt, String)
  UnknownSignalGroupMessageIssue(UInt, String)
  UnknownSignalGroupMemberIssue(UInt, String, String)
  DuplicateGlobalValueTableIssue(String)
  InvalidGlobalValueTableIssue(String)
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
    (Multiplexed(selector), MultiplexedRanges(_, ranges)) =>
      selector_in_range_definitions(selector, ranges)
    (MultiplexedRanges(_, ranges), Multiplexed(selector)) =>
      selector_in_range_definitions(selector, ranges)
    (
      MultiplexedRanges(left_name, left_ranges),
      MultiplexedRanges(right_name, right_ranges),
    ) =>
      if left_name != right_name {
        true
      } else {
        ranges_intersect(left_ranges, right_ranges)
      }
    _ => true
  }
}

///|
fn selector_in_range_definitions(
  selector : Int,
  ranges : Array[MultiplexRange],
) -> Bool {
  for range in ranges {
    if selector >= range.start && selector <= range.end {
      return true
    }
  }
  false
}

///|
fn ranges_intersect(
  left : Array[MultiplexRange],
  right : Array[MultiplexRange],
) -> Bool {
  for a in left {
    for b in right {
      if a.start <= b.end && b.start <= a.end {
        return true
      }
    }
  }
  false
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
  if dbc_message_id_parts(message.id) is None {
    issues.push(InvalidMessageIdentifierIssue(message.id))
  }
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
  for index, transmitter in message.additional_transmitters {
    if transmitter == message.transmitter {
      issues.push(DuplicateMessageTransmitterIssue(message.id, transmitter))
    }
    for previous = 0; previous < index; previous = previous + 1 {
      if message.additional_transmitters[previous] == transmitter {
        issues.push(DuplicateMessageTransmitterIssue(message.id, transmitter))
      }
    }
  }
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
    match signal.value_type {
      Float32 if signal.bit_length != 32 =>
        issues.push(
          InvalidSignalValueTypeIssue(
            message.id,
            signal.name,
            signal.value_type,
            signal.bit_length,
          ),
        )
      Float64 if signal.bit_length != 64 =>
        issues.push(
          InvalidSignalValueTypeIssue(
            message.id,
            signal.name,
            signal.value_type,
            signal.bit_length,
          ),
        )
      _ => ()
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
        if signal.value_type != Integer {
          issues.push(
            FloatingMultiplexerIssue(message.id, signal.name, signal.value_type),
          )
        }
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
      MultiplexedRanges(selector_name, ranges) =>
        match multiplexer {
          None => issues.push(MissingMultiplexerIssue(message.id, signal.name))
          Some(mux) => {
            if mux.name != selector_name {
              issues.push(
                UnknownMultiplexSelectorIssue(
                  message.id,
                  signal.name,
                  selector_name,
                ),
              )
            }
            if ranges.is_empty() {
              issues.push(
                InvalidMultiplexRangeIssue(message.id, signal.name, -1, -1),
              )
            }
            for range in ranges {
              if range.start < 0 || range.end < range.start {
                issues.push(
                  InvalidMultiplexRangeIssue(
                    message.id,
                    signal.name,
                    range.start,
                    range.end,
                  ),
                )
              } else if multiplexer_count == 1 &&
                !multiplex_selector_fits(mux, range.end) {
                issues.push(
                  MultiplexSelectorOutOfRangeIssue(
                    message.id,
                    signal.name,
                    range.end,
                  ),
                )
              }
            }
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
fn validate_comments(
  database : Database,
  issues : Array[ValidationIssue],
) -> Unit {
  for index, comment in database.comments {
    for previous = 0; previous < index; previous = previous + 1 {
      if database.comments[previous].target == comment.target {
        issues.push(DuplicateCommentIssue(comment.target))
      }
    }
    match comment.target {
      DatabaseComment => ()
      NodeComment(node) => {
        let mut found = false
        for candidate in database.nodes {
          if candidate == node {
            found = true
          }
        }
        if !found {
          issues.push(UnknownCommentNodeIssue(node))
        }
      }
      MessageComment(message_id) =>
        if database.find_message(message_id) is None {
          issues.push(UnknownCommentMessageIssue(message_id))
        }
      SignalComment(message_id, signal_name) =>
        match database.find_message(message_id) {
          None => issues.push(UnknownCommentMessageIssue(message_id))
          Some(message) =>
            if message.find_signal(signal_name) is None {
              issues.push(UnknownCommentSignalIssue(message_id, signal_name))
            }
        }
    }
  }
}

///|
fn validate_attributes(
  database : Database,
  issues : Array[ValidationIssue],
) -> Unit {
  let attributes = database.attributes
  for index, definition in attributes.definitions {
    for previous = 0; previous < index; previous = previous + 1 {
      if attributes.definitions[previous].name == definition.name {
        issues.push(DuplicateAttributeDefinitionIssue(definition.name))
      }
    }
    if definition.name.is_empty() ||
      attribute_type_text(definition.value_type) is Err(_) {
      issues.push(InvalidAttributeValueIssue(definition.name))
    }
  }
  for index, default in attributes.defaults {
    for previous = 0; previous < index; previous = previous + 1 {
      if attributes.defaults[previous].name == default.name {
        issues.push(DuplicateAttributeDefaultIssue(default.name))
      }
    }
    match find_attribute_definition(attributes.definitions, default.name) {
      None => issues.push(UnknownAttributeDefinitionIssue(default.name))
      Some(definition) =>
        if attribute_value_text(default.value, definition.value_type) is Err(_) {
          issues.push(InvalidAttributeValueIssue(default.name))
        }
    }
  }
  for index, assignment in attributes.assignments {
    for previous = 0; previous < index; previous = previous + 1 {
      if attributes.assignments[previous].name == assignment.name &&
        attributes.assignments[previous].target == assignment.target {
        issues.push(
          DuplicateAttributeAssignmentIssue(assignment.name, assignment.target),
        )
      }
    }
    match find_attribute_definition(attributes.definitions, assignment.name) {
      None => issues.push(UnknownAttributeDefinitionIssue(assignment.name))
      Some(definition) => {
        if definition.scope != attribute_target_scope(assignment.target) {
          issues.push(
            AttributeScopeMismatchIssue(assignment.name, assignment.target),
          )
        }
        if !attribute_target_exists(
            database.nodes,
            database.messages,
            assignment.target,
          ) {
          issues.push(
            InvalidAttributeTargetIssue(assignment.name, assignment.target),
          )
        }
        if attribute_value_text(assignment.value, definition.value_type)
          is Err(_) {
          issues.push(InvalidAttributeValueIssue(assignment.name))
        }
      }
    }
  }
}

///|
fn validate_signal_groups(
  database : Database,
  issues : Array[ValidationIssue],
) -> Unit {
  for index, group in database.signal_groups {
    for previous = 0; previous < index; previous = previous + 1 {
      let candidate = database.signal_groups[previous]
      if candidate.message_id == group.message_id &&
        candidate.name == group.name {
        issues.push(DuplicateSignalGroupIssue(group.message_id, group.name))
      }
    }
    if group.name.is_empty() || group.repetition < 0 || group.signals.is_empty() {
      issues.push(InvalidSignalGroupIssue(group.message_id, group.name))
    }
    match database.find_message(group.message_id) {
      None =>
        issues.push(
          UnknownSignalGroupMessageIssue(group.message_id, group.name),
        )
      Some(message) =>
        for signal_name in group.signals {
          if message.find_signal(signal_name) is None {
            issues.push(
              UnknownSignalGroupMemberIssue(
                group.message_id,
                group.name,
                signal_name,
              ),
            )
          }
        }
    }
  }
}

///|
fn validate_global_value_tables(
  database : Database,
  issues : Array[ValidationIssue],
) -> Unit {
  for index, table in database.global_value_tables {
    for previous = 0; previous < index; previous = previous + 1 {
      if database.global_value_tables[previous].name == table.name {
        issues.push(DuplicateGlobalValueTableIssue(table.name))
      }
    }
    if table.name.is_empty() || table.entries.is_empty() {
      issues.push(InvalidGlobalValueTableIssue(table.name))
    }
    for entry_index, entry in table.entries {
      for previous = 0; previous < entry_index; previous = previous + 1 {
        if table.entries[previous].value == entry.value {
          issues.push(InvalidGlobalValueTableIssue(table.name))
        }
      }
    }
  }
}

///|
/// Validate cross-field and bit-layout constraints that are not syntax errors.
pub fn Database::validate(self : Database) -> Array[ValidationIssue] {
  let issues : Array[ValidationIssue] = []
  validate_comments(self, issues)
  validate_attributes(self, issues)
  validate_global_value_tables(self, issues)
  validate_signal_groups(self, issues)
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
