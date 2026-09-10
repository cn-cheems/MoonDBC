///|
test "parse value descriptions and labels with spaces" {
  let result = @moondbc.parse(
    (
      #|BO_ 100 Transmission: 8 ECU
      #| SG_ Gear : 0|8@1+ (1,0) [0|7] "" Dashboard
      #|VAL_ 100 Gear 0 "Neutral" 1 "Drive" 2 "Reverse gear";
    ),
  )
  assert_true(result.is_valid())
  assert_eq(result.database.value_tables.length(), 1)
  let table = result.database.find_value_table(100U, "Gear").unwrap()
  assert_eq(table.entries.length(), 3)
  assert_eq(table.find_label(0L), Some("Neutral"))
  assert_eq(table.find_label(2L), Some("Reverse gear"))
  assert_eq(table.find_label(3L), None)
  assert_eq(result.database.value_label(100U, "Gear", 1L), Some("Drive"))
}

///|
test "resolve value table declared before its signal" {
  let result = @moondbc.parse(
    (
      #|VAL_ 101 State -1 "Fault" 0 "Off" 1 "On";
      #|BO_ 101 Status: 1 ECU
      #| SG_ State : 0|8@1- (1,0) [-1|1] "" Dashboard
    ),
  )
  assert_true(result.is_valid())
  assert_eq(result.database.value_label(101U, "State", -1L), Some("Fault"))
}

///|
test "report malformed value table" {
  let result = @moondbc.parse(
    (
      #|BO_ 102 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|1] "" Dashboard
      #|VAL_ 102 State 0 "Off" 0 "Again";
      #|VAL_ 102 State 1 "On"
    ),
  )
  assert_eq(result.diagnostics.length(), 2)
  assert_eq(result.diagnostics[0].code, "DBC007")
  assert_eq(result.diagnostics[1].code, "DBC007")
}

///|
test "report unknown value table references" {
  let result = @moondbc.parse(
    (
      #|BO_ 103 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|1] "" Dashboard
      #|VAL_ 999 Missing 0 "Off";
      #|VAL_ 103 Missing 0 "Off";
    ),
  )
  assert_eq(result.diagnostics.length(), 2)
  assert_eq(result.diagnostics[0].code, "DBC008")
  assert_eq(result.diagnostics[1].code, "DBC009")
}

///|
test "report duplicate value tables" {
  let result = @moondbc.parse(
    (
      #|BO_ 104 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|1] "" Dashboard
      #|VAL_ 104 State 0 "Off";
      #|VAL_ 104 State 1 "On";
    ),
  )
  assert_eq(result.database.value_tables.length(), 1)
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "DBC010")
}
