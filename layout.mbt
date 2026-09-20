///|
pub(all) enum FrameLayoutCellKind {
  LayoutUnused
  LayoutOccupied
  LayoutMultiplexed
  LayoutConflict
} derive(Eq, Debug)

///|
pub(all) struct FrameLayoutOwner {
  signal_index : Int
  signal_name : String
  /// Bit position within the raw signal value, where zero is the least
  /// significant bit.
  signal_bit : Int
  multiplex : MultiplexRole
  source : SourceSpan?
} derive(Eq, Debug)

///|
pub(all) struct FrameLayoutCell {
  absolute_bit : Int
  byte_index : Int
  bit_in_byte : Int
  kind : FrameLayoutCellKind
  owners : Array[FrameLayoutOwner]
} derive(Eq, Debug)

///|
pub(all) enum FrameLayoutIssue {
  LayoutInvalidPayloadSize(Int)
  LayoutInvalidSignal(String, Int, Int, SourceSpan?)
  LayoutSignalOutsidePayload(String, SourceSpan?)
  LayoutConflictingSignals(String, String, Array[Int], SourceSpan?, SourceSpan?)
} derive(Eq, Debug)

///|
pub(all) struct FrameLayoutAnalysis {
  message_id : UInt
  payload_size : Int
  cells : Array[FrameLayoutCell]
  issues : Array[FrameLayoutIssue]
} derive(Eq, Debug)

///|
pub(all) enum FrameLayoutError {
  LayoutUnknownMessage(UInt)
} derive(Eq, Debug)

///|
fn layout_roles_can_coexist(
  left : MultiplexRole,
  right : MultiplexRole,
) -> Bool {
  match (left, right) {
    (Multiplexed(left_selector), Multiplexed(right_selector)) =>
      left_selector == right_selector
    _ => true
  }
}

///|
fn layout_signal_source(
  source_map : DbcSourceMap?,
  message_id : UInt,
  signal_name : StringView,
) -> SourceSpan? {
  match source_map {
    Some(map) => map.find_signal(message_id, signal_name)
    None => None
  }
}

///|
fn layout_signal_bits(
  signal : Signal,
  available_bits : Int,
) -> Array[(Int, Int)]? {
  let bits : Array[(Int, Int)] = []
  match signal.byte_order {
    Intel => {
      if signal.bit_length > available_bits ||
        signal.start_bit > available_bits - signal.bit_length {
        return None
      }
      for offset = 0; offset < signal.bit_length; offset = offset + 1 {
        bits.push((signal.start_bit + offset, offset))
      }
    }
    Motorola => {
      let mut absolute_bit = signal.start_bit
      for offset = 0; offset < signal.bit_length; offset = offset + 1 {
        if absolute_bit >= available_bits {
          return None
        }
        bits.push((absolute_bit, signal.bit_length - 1 - offset))
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
fn shared_layout_bits(
  left : Array[(Int, Int)],
  right : Array[(Int, Int)],
) -> Array[Int] {
  let shared : Array[Int] = []
  for left_bit in left {
    for right_bit in right {
      if left_bit.0 == right_bit.0 {
        shared.push(left_bit.0)
      }
    }
  }
  shared
}

///|
fn analyze_message_layout(
  message : Message,
  source_map : DbcSourceMap?,
) -> FrameLayoutAnalysis {
  let issues : Array[FrameLayoutIssue] = []
  let available_bits = if message.payload_size >= 0 &&
    message.payload_size <= 64 {
    message.payload_size * 8
  } else {
    issues.push(LayoutInvalidPayloadSize(message.payload_size))
    0
  }
  let cells : Array[FrameLayoutCell] = []
  for absolute_bit = 0
      absolute_bit < available_bits
      absolute_bit = absolute_bit + 1 {
    cells.push({
      absolute_bit,
      byte_index: absolute_bit / 8,
      bit_in_byte: absolute_bit % 8,
      kind: LayoutUnused,
      owners: [],
    })
  }
  let signal_bits : Array[Array[(Int, Int)]?] = []
  for signal_index, signal in message.signals {
    let source = layout_signal_source(source_map, message.id, signal.name)
    if signal.start_bit < 0 || signal.bit_length < 1 || signal.bit_length > 64 {
      issues.push(
        LayoutInvalidSignal(
          signal.name,
          signal.start_bit,
          signal.bit_length,
          source,
        ),
      )
      signal_bits.push(None)
      continue
    }
    let bits = layout_signal_bits(signal, available_bits)
    match bits {
      None => {
        issues.push(LayoutSignalOutsidePayload(signal.name, source))
        signal_bits.push(None)
      }
      Some(bits) => {
        for bit in bits {
          cells[bit.0].owners.push({
            signal_index,
            signal_name: signal.name,
            signal_bit: bit.1,
            multiplex: signal.multiplex,
            source,
          })
        }
        signal_bits.push(Some(bits))
      }
    }
  }
  for right = 0; right < message.signals.length(); right = right + 1 {
    for left = 0; left < right; left = left + 1 {
      if layout_roles_can_coexist(
          message.signals[left].multiplex,
          message.signals[right].multiplex,
        ) {
        match (signal_bits[left], signal_bits[right]) {
          (Some(left_bits), Some(right_bits)) => {
            let shared = shared_layout_bits(left_bits, right_bits)
            if !shared.is_empty() {
              issues.push(
                LayoutConflictingSignals(
                  message.signals[left].name,
                  message.signals[right].name,
                  shared,
                  layout_signal_source(
                    source_map,
                    message.id,
                    message.signals[left].name,
                  ),
                  layout_signal_source(
                    source_map,
                    message.id,
                    message.signals[right].name,
                  ),
                ),
              )
            }
          }
          _ => ()
        }
      }
    }
  }
  for index, cell in cells {
    let kind = if cell.owners.is_empty() {
      LayoutUnused
    } else if cell.owners.length() == 1 {
      LayoutOccupied
    } else {
      let mut conflict = false
      for right = 0; right < cell.owners.length(); right = right + 1 {
        for left = 0; left < right; left = left + 1 {
          if layout_roles_can_coexist(
              cell.owners[left].multiplex,
              cell.owners[right].multiplex,
            ) {
            conflict = true
          }
        }
      }
      if conflict {
        LayoutConflict
      } else {
        LayoutMultiplexed
      }
    }
    cells[index] = { ..cell, kind, }
  }
  { message_id: message.id, payload_size: message.payload_size, cells, issues, }
}

///|
/// Analyze the payload bits occupied by every signal. Source ranges are absent
/// for databases that were constructed manually or returned by `parse`.
pub fn Database::analyze_frame_layout(
  self : Database,
  message_id : UInt,
) -> Result[FrameLayoutAnalysis, FrameLayoutError] {
  match self.find_message(message_id) {
    Some(message) => Ok(analyze_message_layout(message, None))
    None => Err(LayoutUnknownMessage(message_id))
  }
}

///|
/// Analyze a parsed message and attach its original DBC declaration ranges.
pub fn SourceParseResult::analyze_frame_layout(
  self : SourceParseResult,
  message_id : UInt,
) -> Result[FrameLayoutAnalysis, FrameLayoutError] {
  match self.database.find_message(message_id) {
    Some(message) => Ok(analyze_message_layout(message, Some(self.source_map)))
    None => Err(LayoutUnknownMessage(message_id))
  }
}

///|
pub fn FrameLayoutAnalysis::find_cell(
  self : FrameLayoutAnalysis,
  byte_index : Int,
  bit_in_byte : Int,
) -> FrameLayoutCell? {
  if byte_index < 0 ||
    byte_index >= self.cells.length() / 8 ||
    bit_in_byte < 0 ||
    bit_in_byte > 7 {
    return None
  }
  let absolute_bit = byte_index * 8 + bit_in_byte
  if absolute_bit >= self.cells.length() {
    None
  } else {
    Some(self.cells[absolute_bit])
  }
}
