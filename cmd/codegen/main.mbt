///|
fn main {
  let source =
    #|BO_ 256 Powertrain: 8 ECU
    #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
    #| SG_ Gear : 16|8@1+ (1,0) [0|6] "" Dashboard
    #|VAL_ 256 Gear 0 "Neutral" 1 "Drive" 2 "Reverse";
  let result = @moondbc.parse(source)
  if result.is_valid() {
    println(result.database.generate_moonbit_constants())
  } else {
    println("unable to generate constants from an invalid database")
  }
}
