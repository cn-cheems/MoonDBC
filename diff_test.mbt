///|
test "identical databases have no changes" {
  let source =
    #|VERSION "1"
    #|BU_: ECU
    #|BO_ 400 Status: 1 ECU
    #| SG_ State : 0|8@1+ (1,0) [0|1] "" ECU
    #|VAL_ 400 State 0 "Off" 1 "On";
  let left = @moondbc.parse(source).database
  let right = @moondbc.parse(source).database
  assert_eq(left.diff(right), [])
}

///|
test "compare global and message metadata" {
  let before = @moondbc.parse(
      (
        #|VERSION "1"
        #|BU_: ECU
        #|BO_ 401 OldName: 1 ECU
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|VERSION "2"
        #|BU_: ECU Dashboard
        #|BO_ 401 NewName: 2 Dashboard
      ),
    ).database
  assert_eq(before.diff(after), [
    @moondbc.VersionChangedChange(Some("1"), Some("2")),
    @moondbc.NodesChangedChange(["ECU"], ["ECU", "Dashboard"]),
    @moondbc.MessageMetadataChangedChange(
      401U,
      { name: "OldName", payload_size: 1, transmitter: "ECU", },
      { name: "NewName", payload_size: 2, transmitter: "Dashboard", },
    ),
  ])
}

///|
test "compare added removed and modified comments" {
  let before = @moondbc.parse(
      (
        #|BU_: ECU
        #|BO_ 410 Status: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|1] "" ECU
        #|CM_ "Old database note";
        #|CM_ BO_ 410 "Legacy message note";
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|BU_: ECU
        #|BO_ 410 Status: 1 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|1] "" ECU
        #|CM_ "New database note";
        #|CM_ SG_ 410 State "Signal note";
      ),
    ).database
  assert_eq(before.diff(after), [
    @moondbc.CommentModifiedChange(
      @moondbc.DatabaseComment,
      "Old database note",
      "New database note",
    ),
    @moondbc.CommentRemovedChange(before.comments[1]),
    @moondbc.CommentAddedChange(after.comments[1]),
  ])
}

///|
test "compare added removed and modified signals" {
  let before = @moondbc.parse(
      (
        #|BO_ 402 Data: 2 ECU
        #| SG_ Kept : 0|8@1+ (1,0) [0|255] "" ECU
        #| SG_ Removed : 8|8@1+ (1,0) [0|255] "" ECU
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|BO_ 402 Data: 2 ECU
        #| SG_ Kept : 0|8@1+ (0.5,0) [0|127.5] "V" ECU
        #| SG_ Added : 8|8@1+ (1,0) [0|255] "" ECU
      ),
    ).database
  let changes = before.diff(after)
  let before_kept = before.messages[0].signals[0]
  let before_removed = before.messages[0].signals[1]
  let after_kept = after.messages[0].signals[0]
  let after_added = after.messages[0].signals[1]
  assert_eq(changes, [
    @moondbc.SignalModifiedChange(402U, "Kept", before_kept, after_kept),
    @moondbc.SignalRemovedChange(402U, before_removed),
    @moondbc.SignalAddedChange(402U, after_added),
  ])
}

///|
test "compare added and removed messages" {
  let before = @moondbc.parse(
      (
        #|BO_ 403 Removed: 1 ECU
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|BO_ 404 Added: 2 ECU
      ),
    ).database
  assert_eq(before.diff(after), [
    @moondbc.MessageRemovedChange(before.messages[0]),
    @moondbc.MessageAddedChange(after.messages[0]),
  ])
}

///|
test "compare value table additions removals and modifications" {
  let before = @moondbc.parse(
      (
        #|BO_ 405 Status: 2 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|1] "" ECU
        #| SG_ Legacy : 8|8@1+ (1,0) [0|1] "" ECU
        #|VAL_ 405 State 0 "Off";
        #|VAL_ 405 Legacy 0 "No";
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|BO_ 405 Status: 2 ECU
        #| SG_ State : 0|8@1+ (1,0) [0|1] "" ECU
        #| SG_ Added : 8|8@1+ (1,0) [0|1] "" ECU
        #|VAL_ 405 State 0 "Off" 1 "On";
        #|VAL_ 405 Added 0 "No" 1 "Yes";
      ),
    ).database
  assert_eq(before.diff(after), [
    @moondbc.SignalRemovedChange(405U, before.messages[0].signals[1]),
    @moondbc.SignalAddedChange(405U, after.messages[0].signals[1]),
    @moondbc.ValueTableModifiedChange(
      405U,
      "State",
      before.value_tables[0],
      after.value_tables[0],
    ),
    @moondbc.ValueTableRemovedChange(before.value_tables[1]),
    @moondbc.ValueTableAddedChange(after.value_tables[1]),
  ])
}
