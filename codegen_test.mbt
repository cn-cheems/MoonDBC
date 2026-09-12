///|
test "generate standalone message and signal constants" {
  let database = @moondbc.parse(
      (
        #|BO_ 256 Powertrain: 8 ECU
        #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
        #| SG_ CoolantTemp : 23|8@0- (1,-40) [-40|215] "degC" Dashboard
      ),
    ).database
  assert_eq(
    database.generate_moonbit_constants(),
    (
      #|// MoonDBC static CAN metadata.
      #|
      #|/// Message Powertrain (256).
      #|pub const DBC_POWERTRAIN_256_ID : UInt = 256U
      #|pub const DBC_POWERTRAIN_256_IS_EXTENDED_FRAME : Bool = false
      #|pub const DBC_POWERTRAIN_256_PAYLOAD_SIZE : Int = 8
      #|
      #|/// Signal EngineSpeed in message Powertrain.
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_START_BIT : Int = 0
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_BIT_LENGTH : Int = 16
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_IS_INTEL : Bool = true
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_IS_SIGNED : Bool = false
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_FACTOR : Double = 0.125
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_OFFSET : Double = 0
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_MINIMUM : Double = 0
      #|pub const DBC_POWERTRAIN_256_ENGINESPEED_0_MAXIMUM : Double = 8000
      #|
      #|/// Signal CoolantTemp in message Powertrain.
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_START_BIT : Int = 23
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_BIT_LENGTH : Int = 8
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_IS_INTEL : Bool = false
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_IS_SIGNED : Bool = true
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_FACTOR : Double = 1
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_OFFSET : Double = -40
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_MINIMUM : Double = -40
      #|pub const DBC_POWERTRAIN_256_COOLANTTEMP_1_MAXIMUM : Double = 215
    ),
  )
}

///|
test "generate multiplex and value table constants" {
  let database = @moondbc.parse(
      (
        #|BO_ 600 Controls: 3 ECU
        #| SG_ Mode M : 0|8@1+ (1,0) [0|2] "" ECU
        #| SG_ Torque m1 : 8|16@1- (0.5,-10) [-10|100] "Nm" ECU
        #|VAL_ 600 Mode 0 "Off" 1 "Drive mode";
      ),
    ).database
  let generated = database.generate_moonbit_constants()
  assert_eq(
    generated,
    (
      #|// MoonDBC static CAN metadata.
      #|
      #|/// Message Controls (600).
      #|pub const DBC_CONTROLS_600_ID : UInt = 600U
      #|pub const DBC_CONTROLS_600_IS_EXTENDED_FRAME : Bool = false
      #|pub const DBC_CONTROLS_600_PAYLOAD_SIZE : Int = 3
      #|
      #|/// Signal Mode in message Controls.
      #|pub const DBC_CONTROLS_600_MODE_0_START_BIT : Int = 0
      #|pub const DBC_CONTROLS_600_MODE_0_BIT_LENGTH : Int = 8
      #|pub const DBC_CONTROLS_600_MODE_0_IS_INTEL : Bool = true
      #|pub const DBC_CONTROLS_600_MODE_0_IS_SIGNED : Bool = false
      #|pub const DBC_CONTROLS_600_MODE_0_FACTOR : Double = 1
      #|pub const DBC_CONTROLS_600_MODE_0_OFFSET : Double = 0
      #|pub const DBC_CONTROLS_600_MODE_0_MINIMUM : Double = 0
      #|pub const DBC_CONTROLS_600_MODE_0_MAXIMUM : Double = 2
      #|pub const DBC_CONTROLS_600_MODE_0_IS_MULTIPLEXER : Bool = true
      #|
      #|/// Signal Torque in message Controls.
      #|pub const DBC_CONTROLS_600_TORQUE_1_START_BIT : Int = 8
      #|pub const DBC_CONTROLS_600_TORQUE_1_BIT_LENGTH : Int = 16
      #|pub const DBC_CONTROLS_600_TORQUE_1_IS_INTEL : Bool = true
      #|pub const DBC_CONTROLS_600_TORQUE_1_IS_SIGNED : Bool = true
      #|pub const DBC_CONTROLS_600_TORQUE_1_FACTOR : Double = 0.5
      #|pub const DBC_CONTROLS_600_TORQUE_1_OFFSET : Double = -10
      #|pub const DBC_CONTROLS_600_TORQUE_1_MINIMUM : Double = -10
      #|pub const DBC_CONTROLS_600_TORQUE_1_MAXIMUM : Double = 100
      #|pub const DBC_CONTROLS_600_TORQUE_1_MULTIPLEX_VALUE : Int = 1
      #|
      #|/// Value Off for signal Mode in message 600.
      #|pub const DBC_VALUE_600_MODE_OFF_0 : Int64 = 0L
      #|
      #|/// Value Drive mode for signal Mode in message 600.
      #|pub const DBC_VALUE_600_MODE_DRIVE_MODE_1 : Int64 = 1L
    ),
  )
}

///|
test "generated identifiers are normalized and stable" {
  let database : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [
      {
        id: 700U,
        name: "body-control",
        payload_size: 1,
        transmitter: "ECU",
        additional_transmitters: [],
        signals: [
          {
            name: "door.status",
            start_bit: 0,
            bit_length: 1,
            byte_order: @moondbc.Intel,
            value_kind: @moondbc.Unsigned,
            factor: 1.0,
            offset: 0.0,
            minimum: 0.0,
            maximum: 1.0,
            unit: "",
            receivers: [],
            multiplex: @moondbc.Plain,
          },
        ],
      },
    ],
    value_tables: [],
    comments: [],
  }
  let generated = database.generate_moonbit_constants()
  assert_eq(
    generated,
    (
      #|// MoonDBC static CAN metadata.
      #|
      #|/// Message body-control (700).
      #|pub const DBC_BODY_CONTROL_700_ID : UInt = 700U
      #|pub const DBC_BODY_CONTROL_700_IS_EXTENDED_FRAME : Bool = false
      #|pub const DBC_BODY_CONTROL_700_PAYLOAD_SIZE : Int = 1
      #|
      #|/// Signal door.status in message body-control.
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_START_BIT : Int = 0
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_BIT_LENGTH : Int = 1
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_IS_INTEL : Bool = true
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_IS_SIGNED : Bool = false
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_FACTOR : Double = 1
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_OFFSET : Double = 0
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_MINIMUM : Double = 0
      #|pub const DBC_BODY_CONTROL_700_DOOR_STATUS_0_MAXIMUM : Double = 1
    ),
  )
}

///|
test "empty databases still generate a valid source header" {
  let database : @moondbc.Database = {
    version: None,
    nodes: [],
    messages: [],
    value_tables: [],
    comments: [],
  }
  assert_eq(
    database.generate_moonbit_constants(),
    "// MoonDBC static CAN metadata.",
  )
}
