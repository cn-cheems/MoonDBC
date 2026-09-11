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
  let payload = b"\x40\x1f\x00\x00\x00\x00\x00\x00"
  for message in result.database.messages {
    println(
      "id=\{message.id} \{message.name}: \{message.signals.length()} signal(s)",
    )
    for signal in message.signals {
      println(
        "  \{signal.name} start=\{signal.start_bit} length=\{signal.bit_length} unit=\{signal.unit}",
      )
    }
    match result.database.decode_frame(message.id, payload) {
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
