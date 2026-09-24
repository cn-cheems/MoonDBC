///|
test "workbench sample produces a source-aware multiplexed layout" {
  let parsed = @moondbc.parse_with_source_map(sample_dbc)
  assert_eq(parsed.diagnostics, [])
  assert_eq(parsed.database.messages.length(), 2)
  let layout = parsed.analyze_frame_layout(512U).unwrap()
  let shared = layout.find_cell(1, 0).unwrap()
  assert_eq(shared.kind, @moondbc.LayoutMultiplexed)
  assert_eq(shared.owners.length(), 2)
  assert_eq(shared.owners[0].source.unwrap().start_line, 16)
  assert_eq(shared.owners[1].source.unwrap().start_line, 17)
}

///|
test "local imports validate file metadata before reading" {
  assert_eq(validate_import_metadata("", -1), Some("No file was selected."))
  assert_eq(
    validate_import_metadata("network.txt", 128),
    Some("Choose a file with the .dbc extension."),
  )
  assert_eq(validate_import_metadata("network.DBC", max_import_bytes), None)
  assert_eq(
    validate_import_metadata("network.dbc", max_import_bytes + 1),
    Some("The file exceeds the 4 MiB import limit."),
  )
}
