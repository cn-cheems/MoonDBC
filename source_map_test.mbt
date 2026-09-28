///|
test "locate semantic overlaps at the later signal declaration" {
  let parsed = @moondbc.parse_with_source_map(
    (
      #|BO_ 300 Status: 1 ECU
      #| SG_ First : 0|8@1+ (1,0) [0|255] "" ECU
      #| SG_ Second : 4|4@1+ (1,0) [0|15] "" ECU
    ),
  )
  assert_eq(parsed.diagnostics, [])
  let issues = parsed.locate_validation_issues()
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].source.unwrap().start_line, 3)
  assert_eq(issues[0].source.unwrap().start_column, 2)
  assert_eq(
    issues[0].issue.description(),
    "signals First and Second overlap in message 12C standard",
  )
}

///|
test "locate message-level semantic failures on the message declaration" {
  let parsed = @moondbc.parse_with_source_map(
    (
      #|BO_ 300 Status: 1 ECU
      #| SG_ ModeA M : 0|4@1+ (1,0) [0|15] "" ECU
      #| SG_ ModeB M : 4|4@1+ (1,0) [0|15] "" ECU
    ),
  )
  assert_eq(parsed.diagnostics, [])
  let issues = parsed.locate_validation_issues()
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].source.unwrap().start_line, 1)
  assert_eq(
    issues[0].issue.description(),
    "message 12C standard has multiple multiplexers",
  )
}

///|
test "source map retains comment declaration ranges for unresolved targets" {
  let parsed = @moondbc.parse_with_source_map(
    (
      #|CM_ BU_ Missing "Unknown node";
      #|CM_ BO_ 999 "Unknown message";
    ),
  )
  assert_eq(parsed.diagnostics.length(), 2)
  assert_eq(
    parsed.source_map.find_comment(@moondbc.NodeComment("Missing")).unwrap().start_line,
    1,
  )
  assert_eq(
    parsed.source_map.find_comment(@moondbc.MessageComment(999U)).unwrap().start_line,
    2,
  )
}

///|
test "locate compatibility changes in both DBC revisions" {
  let before = @moondbc.parse_with_source_map(
    (
      #|VERSION "1"
      #|BO_ 256 Status: 3 ECU
      #| SG_ Speed : 0|8@1+ (1,0) [0|255] "" ECU
      #| SG_ State : 8|8@1+ (1,0) [0|255] "" ECU
      #|CM_ BO_ 256 "Old";
      #|VAL_ 256 State 0 "Off";
    ),
  )
  let after = @moondbc.parse_with_source_map(
    (
      #|VERSION "2"
      #|BO_ 256 Status: 3 ECU
      #| SG_ Speed : 0|8@1+ (2,0) [0|510] "" ECU
      #| SG_ State : 8|8@1+ (1,0) [0|255] "" ECU
      #| SG_ Added : 16|8@1+ (1,0) [0|255] "" ECU
      #|CM_ BO_ 256 "New";
      #|VAL_ 256 State 0 "Stopped";
    ),
  )
  assert_eq(before.diagnostics, [])
  assert_eq(after.diagnostics, [])
  let changes = before.diff_with_locations(after)
  assert_eq(changes.length(), 5)
  assert_eq(changes[0].before, None)
  assert_eq(changes[0].after, None)
  assert_eq(changes[1].before.unwrap().start_line, 5)
  assert_eq(changes[1].after.unwrap().start_line, 6)
  assert_eq(changes[2].before.unwrap().start_line, 3)
  assert_eq(changes[2].after.unwrap().start_line, 3)
  assert_eq(changes[3].before, None)
  assert_eq(changes[3].after.unwrap().start_line, 5)
  assert_eq(changes[4].before.unwrap().start_line, 6)
  assert_eq(changes[4].after.unwrap().start_line, 7)
}
