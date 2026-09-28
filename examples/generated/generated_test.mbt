///|
test "generated codec encodes and decodes a physical signal value" {
  let payload = @generated.encode_dbc_status_256_state_0(b"\x00", 42.5).unwrap()
  assert_eq(payload, b"\x55")
  assert_eq(@generated.decode_dbc_status_256_state_0(payload), Ok(42.5))
}
