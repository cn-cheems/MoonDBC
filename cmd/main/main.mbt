///|
fn main {
  let source =
    #|VERSION "demo"
    #|BU_: ECU Dashboard
    #|BO_ 256 Powertrain: 8 ECU
    #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
    #| SG_ CoolantTemp : 23|8@0- (1,-40) [-40|215] "degC" Dashboard
    #| SG_ Gear : 32|8@1+ (1,0) [0|7] "" Dashboard
    #|VAL_ 256 Gear 0 "Neutral" 1 "Drive" 2 "Reverse";
  let result = @moondbc.parse(source)
  println("MoonDBC parsed \{result.database.messages.length()} message(s)")
  println("validation issues: \{result.database.validate().length()}")
  println(
    "self comparison changes: \{result.database.diff(result.database).length()}",
  )
  let report = result.database.compatibility_report(result.database)
  println("backward compatible: \{report.is_backward_compatible()}")
  println("canonical DBC length: \{result.database.to_dbc().unwrap().length()}")
  let payload = result.database
    .encode_frame(256U, [
      { name: "EngineSpeed", physical: 1000.0, },
      { name: "CoolantTemp", physical: -40.0, },
      { name: "Gear", physical: 0.0, },
    ])
    .unwrap()
  let frame : @moondbc.CanFrame = {
    id: 256U,
    is_extended_frame: false,
    payload,
  }
  println("SocketCAN frame: \{frame.to_text().unwrap()}")
  let trace = result.database.decode_trace(frame.to_text().unwrap())
  println("trace rows: \{trace.frames.length()}")
  for message in result.database.messages {
    println(
      "id=\{message.id} \{message.name}: \{message.signals.length()} signal(s)",
    )
    for signal in message.signals {
      println(
        "  \{signal.name} start=\{signal.start_bit} length=\{signal.bit_length} unit=\{signal.unit}",
      )
    }
    match result.database.decode_can_frame(frame) {
      Ok(decoded) =>
        for signal in decoded.signals {
          match signal.label {
            Some(label) => println("  decoded \{signal.name}=\{label}")
            None =>
              println(
                "  decoded \{signal.name}=\{signal.physical} \{signal.unit}",
              )
          }
        }
      Err(_) => println("  unable to decode frame")
    }
  }
  for diagnostic in result.diagnostics {
    println(
      "line \{diagnostic.line} [\{diagnostic.code}] \{diagnostic.message}",
    )
  }
}
