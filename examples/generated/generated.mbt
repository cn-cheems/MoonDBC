// MoonDBC signal codecs. Import cn-cheems/moondbc as @moondbc.

///|
/// Signal 0 of DBC message 256.
fn dbc_status_256_state_0_signal() -> @moondbc.Signal {
  {
    name: "",
    start_bit: 0,
    bit_length: 8,
    byte_order: @moondbc.Intel,
    value_kind: @moondbc.Unsigned,
    value_type: @moondbc.Integer,
    factor: 0.5,
    offset: 0,
    minimum: 0,
    maximum: 127.5,
    unit: "",
    receivers: [],
    multiplex: @moondbc.Plain,
  }
}

///|
pub fn decode_dbc_status_256_state_0(
  payload : BytesView,
) -> Result[Double, @moondbc.DecodeError] {
  dbc_status_256_state_0_signal().decode(payload)
}

///|
pub fn encode_dbc_status_256_state_0(
  payload : BytesView,
  physical : Double,
) -> Result[Bytes, @moondbc.EncodeError] {
  dbc_status_256_state_0_signal().encode(payload, physical)
}
