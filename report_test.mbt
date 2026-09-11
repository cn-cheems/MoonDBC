///|
test "identical databases produce a compatible empty report" {
  let database = @moondbc.parse(
      (
        #|VERSION "1"
        #|BO_ 500 Status: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|1] "" ECU
      ),
    ).database
  let report = database.compatibility_report(database)
  assert_eq(report.has_changes(), false)
  assert_eq(report.is_backward_compatible(), true)
  assert_eq(report.breaking_count, 0)
  assert_eq(report.non_breaking_count, 0)
  assert_eq(report.informational_count, 0)
  assert_eq(
    report.to_markdown(),
    (
      #|# DBC Compatibility Report
      #|
      #|- Breaking changes: 0
      #|- Non-breaking changes: 0
      #|- Informational changes: 0
      #|
      #|No changes detected.
    ),
  )
}

///|
test "report classifies additions as backward compatible" {
  let before = @moondbc.parse(
      (
        #|BO_ 501 Existing: 1 ECU
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|BO_ 501 Existing: 1 ECU
        #|BO_ 502 Added: 1 ECU
      ),
    ).database
  let report = before.compatibility_report(after)
  assert_eq(report.is_backward_compatible(), true)
  assert_eq(report.breaking_count, 0)
  assert_eq(report.non_breaking_count, 1)
  assert_eq(report.informational_count, 0)
  assert_eq(report.changes[0].impact, @moondbc.NonBreaking)
  assert_eq(
    report.changes[0].change.summary(),
    "Message 502 (Added) was added.",
  )
}

///|
test "report detects breaking and informational changes" {
  let before = @moondbc.parse(
      (
        #|VERSION "1"
        #|BO_ 503 Removed: 1 ECU
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|VERSION "2"
        #|BO_ 504 Added: 2 ECU
      ),
    ).database
  let report = before.compatibility_report(after)
  assert_eq(report.is_backward_compatible(), false)
  assert_eq(report.breaking_count, 1)
  assert_eq(report.non_breaking_count, 1)
  assert_eq(report.informational_count, 1)
  assert_eq(report.changes[0].impact, @moondbc.Informational)
  assert_eq(report.changes[1].impact, @moondbc.Breaking)
  assert_eq(report.changes[2].impact, @moondbc.NonBreaking)
  assert_eq(
    report.to_markdown(),
    (
      #|# DBC Compatibility Report
      #|
      #|- Breaking changes: 1
      #|- Non-breaking changes: 1
      #|- Informational changes: 1
      #|
      #|## Changes
      #|
      #|- **Informational**: DBC version changed from "1" to "2".
      #|- **Breaking**: Message 503 (Removed) was removed.
      #|- **Non-breaking**: Message 504 (Added) was added.
    ),
  )
}

///|
test "change impact covers signal and value table updates" {
  let database = @moondbc.parse(
      (
        #|BO_ 505 Status: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|1] "" ECU
        #|VAL_ 505 State 0 "Off";
      ),
    ).database
  let message = database.messages[0]
  let signal = message.signals[0]
  let table = database.value_tables[0]
  assert_eq(
    @moondbc.SignalAddedChange(505U, signal).impact(),
    @moondbc.NonBreaking,
  )
  assert_eq(
    @moondbc.SignalRemovedChange(505U, signal).impact(),
    @moondbc.Breaking,
  )
  assert_eq(
    @moondbc.ValueTableModifiedChange(505U, "State", table, table).impact(),
    @moondbc.Breaking,
  )
}
