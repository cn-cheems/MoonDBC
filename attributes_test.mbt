///|
test "resolve common DBC attributes and retain their values" {
  let source =
    #|VERSION ""
    #|BU_: ECU Logger
    #|BA_ "BusType" "CAN";
    #|BA_ "GenMsgCycleTime" BO_ 100 20;
    #|BA_ "NodeNumber" BU_ ECU 7;
    #|BA_ "GenSigStartValue" SG_ 100 State 1.5;
    #|BO_ 100 Status: 1 ECU
    #| SG_ State : 0|8@1+ (1,0) [0|255] "" Logger
    #|BO_ 101 Other: 1 ECU
    #| SG_ OtherState : 0|8@1+ (1,0) [0|255] "" Logger
    #|BA_DEF_ "BusType" STRING ;
    #|BA_DEF_ BO_ "GenMsgCycleTime" INT 0 65535;
    #|BA_DEF_ BU_ "NodeNumber" HEX 0 255;
    #|BA_DEF_ SG_ "GenSigStartValue" FLOAT 0 255;
    #|BA_DEF_DEF_ "BusType" "Unknown";
    #|BA_DEF_DEF_ "GenMsgCycleTime" 100;
  let parsed = @moondbc.parse(source)
  assert_eq(parsed.diagnostics, [])
  let database = parsed.database
  assert_eq(database.attributes.definitions.length(), 4)
  assert_eq(database.attributes.defaults.length(), 2)
  assert_eq(database.attributes.assignments.length(), 4)
  assert_eq(
    database.attribute_value("BusType", @moondbc.DatabaseAttributeTarget),
    Some(@moondbc.AttributeText("CAN")),
  )
  assert_eq(
    database.attribute_value(
      "GenMsgCycleTime",
      @moondbc.MessageAttributeTarget(100U),
    ),
    Some(@moondbc.AttributeInteger(20L)),
  )
  assert_eq(
    database.attribute_value(
      "GenMsgCycleTime",
      @moondbc.MessageAttributeTarget(101U),
    ),
    Some(@moondbc.AttributeInteger(100L)),
  )
  assert_eq(
    database.attribute_value(
      "GenMsgCycleTime",
      @moondbc.MessageAttributeTarget(999U),
    ),
    None,
  )
  assert_eq(
    database.attribute_value(
      "GenSigStartValue",
      @moondbc.SignalAttributeTarget(100U, "State"),
    ),
    Some(@moondbc.AttributeFloat(1.5)),
  )
  assert_eq(database.validate(), [])
  let written = database.to_dbc().unwrap()
  assert_eq(@moondbc.parse(written).database, database)
  let formatted = @moondbc.run_format_cli("attributes.dbc", source, false)
  assert_eq(formatted.exit_code, 0)
  assert_eq(@moondbc.parse(formatted.stdout).database, database)
  assert_eq(
    @moondbc.run_format_cli("attributes.dbc", formatted.stdout, true).exit_code,
    0,
  )
}

///|
test "round trip enum attribute defaults and numeric assignments" {
  let parsed = @moondbc.parse(
    (
      #|BU_: ECU
      #|BO_ 101 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
      #|BA_DEF_ BO_ "SendType" ENUM "Cyclic","OnChange";
      #|BA_DEF_DEF_ "SendType" "Cyclic";
      #|BA_ "SendType" BO_ 101 1;
    ),
  )
  assert_eq(parsed.diagnostics, [])
  assert_eq(
    parsed.database.attribute_value(
      "SendType",
      @moondbc.MessageAttributeTarget(101U),
    ),
    Some(@moondbc.AttributeInteger(1L)),
  )
  assert_eq(
    @moondbc.parse(parsed.database.to_dbc().unwrap()).database,
    parsed.database,
  )
}

///|
test "keep commas inside quoted enum choices" {
  let parsed = @moondbc.parse(
    (
      #|BU_: ECU
      #|BA_DEF_ "Mode" ENUM "Cruise, low","Cruise, high";
      #|BA_DEF_DEF_ "Mode" "Cruise, low";
      #|BA_ "Mode" "Cruise, high";
    ),
  )
  assert_eq(parsed.diagnostics, [])
  assert_eq(
    parsed.database.attribute_value("Mode", @moondbc.DatabaseAttributeTarget),
    Some(@moondbc.AttributeText("Cruise, high")),
  )
  assert_eq(
    @moondbc.parse(parsed.database.to_dbc().unwrap()).database,
    parsed.database,
  )
}

///|
test "diagnose invalid attribute references without dropping valid assignments" {
  let parsed = @moondbc.parse(
    (
      #|BU_: ECU
      #|BO_ 102 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
      #|BA_DEF_ BO_ "Cycle" INT 0 1000;
      #|BA_DEF_ BO_ "Cycle" INT 0 1000;
      #|BA_ "Cycle" BO_ 102 20;
      #|BA_ "Cycle" BO_ 102 30;
      #|BA_ "Cycle" SG_ 102 State 20;
      #|BA_ "Cycle" BO_ 999 20;
      #|BA_ "Missing" BO_ 102 20;
    ),
  )
  assert_eq(parsed.diagnostics.length(), 5)
  assert_eq(parsed.diagnostics[0].code, "DBC032")
  assert_eq(parsed.diagnostics[1].code, "DBC041")
  assert_eq(parsed.diagnostics[2].code, "DBC039")
  assert_eq(parsed.diagnostics[3].code, "DBC040")
  assert_eq(parsed.diagnostics[4].code, "DBC038")
  assert_eq(parsed.database.attributes.assignments.length(), 1)
}

///|
test "report attribute metadata changes as compatibility changes" {
  let before = @moondbc.parse(
      (
        #|BU_: ECU
        #|BA_DEF_ "BusType" STRING ;
        #|BA_ "BusType" "CAN";
      ),
    ).database
  let after = @moondbc.parse(
      (
        #|BU_: ECU
        #|BA_DEF_ "BusType" STRING ;
        #|BA_ "BusType" "CAN FD";
      ),
    ).database
  assert_eq(before.diff(after).length(), 1)
  assert_eq(before.compatibility_report(after).breaking_count, 1)
}

///|
test "validate attribute scope and value in manually built models" {
  let parsed = @moondbc.parse(
    (
      #|BU_: ECU
      #|BO_ 105 Status: 1 ECU
      #| SG_ State : 0|8@1+ (1,0) [0|255] "" ECU
      #|BA_DEF_ "BusType" STRING ;
    ),
  )
  let database = {
    ..parsed.database,
    attributes: {
      ..parsed.database.attributes,
      assignments: [
        {
          name: "BusType",
          target: @moondbc.MessageAttributeTarget(105U),
          value: @moondbc.AttributeInteger(1L),
        },
      ],
    },
  }
  assert_eq(database.validate(), [
    @moondbc.AttributeScopeMismatchIssue(
      "BusType",
      @moondbc.MessageAttributeTarget(105U),
    ),
    @moondbc.InvalidAttributeValueIssue("BusType"),
  ])
  assert_eq(
    database.to_dbc(),
    Err(@moondbc.DbcWriteInvalidAttribute("assignment scope does not match")),
  )
}
