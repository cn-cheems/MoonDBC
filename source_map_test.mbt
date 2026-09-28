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
