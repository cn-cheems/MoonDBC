///|
fn invariant_signal(
  start_bit : Int,
  bit_length : Int,
  byte_order : @moondbc.ByteOrder,
  value_kind : @moondbc.ValueKind,
) -> @moondbc.Signal {
  {
    name: "Probe",
    start_bit,
    bit_length,
    byte_order,
    value_kind,
    value_type: @moondbc.Integer,
    factor: 1.0,
    offset: 0.0,
    minimum: -1.0e20,
    maximum: 1.0e20,
    unit: "",
    receivers: [],
    multiplex: @moondbc.Plain,
  }
}

///|
test "raw codec round trips signed and unsigned bit boundaries" {
  let base = b"\xaa\x55\xa5\x5a\x0f\xf0\x33\xcc"
  let mut valid_layouts = 0
  for order in [@moondbc.Intel, @moondbc.Motorola] {
    for length in [1, 2, 3, 7, 8, 9, 12, 16, 31, 32, 33, 63, 64] {
      let mut valid_for_length = 0
      for start = 0; start < 64; start = start + 1 {
        for kind in [@moondbc.Unsigned, @moondbc.Signed] {
          let signal = invariant_signal(start, length, order, kind)
          let values : Array[@moondbc.RawValue] = match kind {
            @moondbc.Unsigned => {
              let maximum = if length == 64 {
                0UL.lnot()
              } else {
                (1UL << length) - 1UL
              }
              [
                @moondbc.UnsignedRaw(0UL),
                @moondbc.UnsignedRaw(maximum / 2UL),
                @moondbc.UnsignedRaw(maximum),
              ]
            }
            @moondbc.Signed => {
              let minimum = if length == 64 {
                -9223372036854775807L - 1L
              } else {
                -(1L << (length - 1))
              }
              let maximum = if length == 64 {
                9223372036854775807L
              } else {
                (1L << (length - 1)) - 1L
              }
              [
                @moondbc.SignedRaw(minimum),
                @moondbc.SignedRaw(-1L),
                @moondbc.SignedRaw(0L),
                @moondbc.SignedRaw(maximum),
              ]
            }
          }
          match signal.encode_raw(base, values[0]) {
            Ok(_) => {
              valid_layouts += 1
              valid_for_length += 1
              for value in values {
                let encoded = signal.encode_raw(base, value).unwrap()
                assert_eq(signal.decode_raw(encoded), Ok(value))
                assert_eq(base, b"\xaa\x55\xa5\x5a\x0f\xf0\x33\xcc")
              }
            }
            Err(@moondbc.EncodeFrameTooShort(_, _)) => ()
            Err(_) => assert_true(false)
          }
        }
      }
      assert_true(valid_for_length >= 2)
    }
  }
  assert_true(valid_layouts > 100)
}
