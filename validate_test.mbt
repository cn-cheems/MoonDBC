///|
test "accept valid multiplexed layouts with shared branch bits" {
  let result = @moondbc.parse(
    (
      #|BO_ 300 Sensor: 2 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" Logger
      #| SG_ Voltage m1 : 8|8@1+ (0.5,0) [0|127.5] "V" Logger
      #| SG_ Current m2 : 8|8@1+ (0.25,0) [0|63.75] "A" Logger
    ),
  )
  assert_eq(result.database.validate(), [])
}

///|
test "detect overlapping active and same-branch signals" {
  let active = @moondbc.parse(
    (
      #|BO_ 301 Overlap: 2 ECU
      #| SG_ First : 0|8@1+ (1,0) [0|255] "" Logger
      #| SG_ Second : 4|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  assert_eq(active.database.validate(), [
    @moondbc.OverlappingSignalsIssue(301U, "First", "Second"),
  ])
  let branch = @moondbc.parse(
    (
      #|BO_ 302 BranchOverlap: 2 ECU
      #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" Logger
      #| SG_ First m1 : 8|8@1+ (1,0) [0|255] "" Logger
      #| SG_ Second m1 : 8|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  assert_eq(branch.database.validate(), [
    @moondbc.OverlappingSignalsIssue(302U, "First", "Second"),
  ])
}

///|
test "detect Intel and Motorola signals outside payload" {
  let result = @moondbc.parse(
    (
      #|BO_ 303 TooSmall: 1 ECU
      #| SG_ IntelOutside : 8|1@1+ (1,0) [0|1] "" Logger
      #| SG_ MotorolaOutside : 7|16@0+ (1,0) [0|65535] "" Logger
    ),
  )
  assert_eq(result.database.validate(), [
    @moondbc.SignalOutsidePayloadIssue(303U, "IntelOutside"),
    @moondbc.SignalOutsidePayloadIssue(303U, "MotorolaOutside"),
  ])
}

///|
test "detect invalid multiplex configurations" {
  let missing = @moondbc.parse(
    (
      #|BO_ 304 Missing: 1 ECU
      #| SG_ Branch m1 : 0|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  assert_eq(missing.database.validate(), [
    @moondbc.MissingMultiplexerIssue(304U, "Branch"),
  ])
  let duplicate = @moondbc.parse(
    (
      #|BO_ 305 Duplicate: 1 ECU
      #| SG_ First M : 0|4@1+ (1,0) [0|15] "" Logger
      #| SG_ Second M : 4|4@1+ (1,0) [0|15] "" Logger
    ),
  )
  assert_eq(duplicate.database.validate(), [
    @moondbc.MultipleMultiplexersIssue(305U),
  ])
  let out_of_range = @moondbc.parse(
    (
      #|BO_ 306 Selector: 2 ECU
      #| SG_ Mode M : 0|2@1+ (1,0) [0|3] "" Logger
      #| SG_ Branch m4 : 8|8@1+ (1,0) [0|255] "" Logger
    ),
  )
  assert_eq(out_of_range.database.validate(), [
    @moondbc.MultiplexSelectorOutOfRangeIssue(306U, "Branch", 4),
  ])
}

///|
test "detect unusable signal scale" {
  let result = @moondbc.parse(
    (
      #|BO_ 307 Scale: 1 ECU
      #| SG_ Frozen : 0|8@1+ (0,5) [0|10] "" Logger
    ),
  )
  assert_eq(result.database.validate(), [
    @moondbc.InvalidScaleIssue(307U, "Frozen", 0.0, 5.0),
  ])
}

///|
test "validate manually constructed signal metadata" {
  let signal : @moondbc.Signal = {
    name: "Broken",
    start_bit: -1,
    bit_length: 0,
    byte_order: @moondbc.Intel,
    value_kind: @moondbc.Unsigned,
    value_type: @moondbc.Integer,
    factor: 1.0,
    offset: 0.0,
    minimum: 10.0,
    maximum: 0.0,
    unit: "",
    receivers: [],
    multiplex: @moondbc.Plain,
  }
  let message : @moondbc.Message = {
    id: 308U,
    name: "Manual",
    payload_size: 1,
    transmitter: "ECU",
    additional_transmitters: [],
    signals: [signal],
  }
  let database : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [message],
    value_tables: [],
    comments: [],
  }
  assert_eq(database.validate(), [
    @moondbc.InvalidSignalLayoutIssue(308U, "Broken", -1, 0),
    @moondbc.InvalidPhysicalRangeIssue(308U, "Broken", 10.0, 0.0),
  ])
}
