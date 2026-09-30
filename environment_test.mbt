///|
test "environment variables and data lengths round trip" {
  let source =
    #|ENVVAR_DATA_ Payload : 16;
    #|EV_ V2CTxTime : 0 [0|60000] "ms" 2000 1 DUMMY_NODE_VECTOR1 V2C;
    #|EV_ Payload : 2 [0|1] "" 0 2 DUMMY_NODE_VECTOR2 ECU,Logger;
  let parsed = @moondbc.parse_with_source_map(source)
  assert_eq(parsed.diagnostics, [])
  assert_eq(parsed.database.environment_variables.length(), 2)
  let timer = parsed.database.find_environment_variable("V2CTxTime").unwrap()
  assert_eq(timer.initial_value, 2000.0)
  assert_eq(timer.access_type, 1)
  assert_eq(timer.access_nodes, ["V2C"])
  let payload = parsed.database.find_environment_variable("Payload").unwrap()
  assert_eq(payload.data_size, Some(16U))
  assert_eq(payload.access_nodes, ["ECU", "Logger"])
  assert_eq(
    parsed.source_map.find_environment_variable("Payload").unwrap().start_line,
    3,
  )
  let written = parsed.database.to_dbc().unwrap()
  let reparsed = @moondbc.parse(written)
  assert_eq(reparsed.diagnostics, [])
  assert_eq(reparsed.database, parsed.database)
}

///|
test "environment data declarations reject unknown and duplicate variables" {
  let parsed = @moondbc.parse(
    (
      #|ENVVAR_DATA_ Missing : 8;
      #|EV_ Counter : 0 [0|100] "" 0 1 DUMMY_NODE_VECTOR1 ECU;
      #|ENVVAR_DATA_ Counter : 4;
      #|ENVVAR_DATA_ Counter : 8;
      #|EV_ Counter : 0 [0|100] "" 0 1 DUMMY_NODE_VECTOR1 ECU;
    ),
  )
  assert_eq(parsed.diagnostics.length(), 3)
  assert_eq(parsed.diagnostics[0].code, "DBC050")
  assert_eq(parsed.diagnostics[1].code, "DBC052")
  assert_eq(parsed.diagnostics[2].code, "DBC053")
}

///|
test "environment variable changes are located and classified" {
  let before = @moondbc.parse_with_source_map(
    "EV_ Counter : 0 [0|100] \"\" 0 1 DUMMY_NODE_VECTOR1 ECU;",
  )
  let after = @moondbc.parse_with_source_map(
    "EV_ Counter : 0 [0|200] \"\" 0 1 DUMMY_NODE_VECTOR1 ECU;",
  )
  let changes = before.diff_with_locations(after)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].before.unwrap().start_line, 1)
  assert_eq(changes[0].after.unwrap().start_line, 1)
  let report = before.database.compatibility_report(after.database)
  assert_eq(report.breaking_count, 1)
}

///|
test "environment variable numeric bounds are validated" {
  let parsed = @moondbc.parse_with_source_map(
    "EV_ Counter : 0 [100|0] \"\" 0 1 DUMMY_NODE_VECTOR1 ECU;",
  )
  assert_eq(parsed.diagnostics, [])
  let issues = parsed.locate_validation_issues()
  assert_eq(issues.length(), 1)
  assert_eq(
    issues[0].issue,
    @moondbc.InvalidEnvironmentVariableIssue("Counter"),
  )
  assert_eq(issues[0].source.unwrap().start_line, 1)
  assert_eq(
    parsed.database.to_dbc(),
    Err(@moondbc.DbcWriteInvalidEnvironmentVariable("Counter")),
  )
}

///|
test "malformed environment declarations cannot be silently dropped" {
  let parsed = @moondbc.parse(
    (
      #|EV_ Broken : 0 [0|1] "" 0 1 DUMMY_NODE_VECTOR4 ECU;
      #|ENVVAR_DATA_ Broken : nope;
    ),
  )
  assert_eq(parsed.database.environment_variables.length(), 0)
  assert_eq(parsed.diagnostics.length(), 2)
  assert_eq(parsed.diagnostics[0].code, "DBC049")
  assert_eq(parsed.diagnostics[1].code, "DBC051")
}
