///|
test "parse, find, and write global DBC value tables" {
  let source =
    #|BU_: ECU Dashboard
    #|
    #|BO_ 430 Status: 1 ECU
    #| SG_ State : 0|2@1+ (1,0) [0|3] "" Dashboard
    #|
    #|VAL_TABLE_ StateNames 0 "Off" 1 "On" 2 "Fault \"entry\"";
  let parsed = @moondbc.parse(source)
  assert_eq(parsed.diagnostics, [])
  let table = parsed.database.find_global_value_table("StateNames").unwrap()
  assert_eq(table.entries[1], { value: 1L, label: "On", })
  assert_eq(table.entries[2], { value: 2L, label: "Fault \"entry\"", })
  let written = parsed.database.to_dbc().unwrap()
  assert_eq(written, source)
  let reparsed = @moondbc.parse(written)
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, parsed.database)
}

///|
test "global value tables preserve source locations and compatibility changes" {
  let before = @moondbc.parse_with_source_map(
    "VAL_TABLE_ StateNames 0 \"Off\" 1 \"On\";",
  )
  let after = @moondbc.parse_with_source_map(
    "VAL_TABLE_ StateNames 0 \"Off\" 1 \"Enabled\";",
  )
  assert_eq(before.diagnostics, [])
  assert_eq(
    before.source_map.find_global_value_table("StateNames").unwrap().start_line,
    1,
  )
  let changes = before.diff_with_locations(after)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].before.unwrap().start_line, 1)
  assert_eq(changes[0].after.unwrap().start_line, 1)
  assert_eq(changes[0].change.impact(), @moondbc.Breaking)
}

///|
test "global value tables reject malformed and duplicate declarations" {
  let malformed = @moondbc.parse("VAL_TABLE_ StateNames;")
  assert_eq(malformed.diagnostics, [
    {
      line: 1,
      column: 1,
      code: "DBC047",
      message: "global value table requires an entry",
    },
  ])
  let duplicate = @moondbc.parse(
    (
      #|VAL_TABLE_ StateNames 0 "Off";
      #|VAL_TABLE_ StateNames 1 "On";
    ),
  )
  assert_eq(duplicate.diagnostics, [
    {
      line: 2,
      column: 1,
      code: "DBC048",
      message: "duplicate global value table name",
    },
  ])
}
