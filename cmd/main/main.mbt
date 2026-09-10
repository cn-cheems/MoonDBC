///|
fn main {
  let source =
    #|VERSION "demo"
    #|BU_: ECU Dashboard
    #|BO_ 256 Powertrain: 8 ECU
    #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
    #| SG_ CoolantTemp : 23|8@0- (1,-40) [-40|215] "degC" Dashboard
  let result = @moondbc.parse(source)
  println("MoonDBC parsed \{result.database.messages.length()} message(s)")
  for message in result.database.messages {
    println(
      "id=\{message.id} \{message.name}: \{message.signals.length()} signal(s)",
    )
    for signal in message.signals {
      println(
        "  \{signal.name} start=\{signal.start_bit} length=\{signal.bit_length} unit=\{signal.unit}",
      )
    }
  }
  for diagnostic in result.diagnostics {
    println(
      "line \{diagnostic.line} [\{diagnostic.code}] \{diagnostic.message}",
    )
  }
}
