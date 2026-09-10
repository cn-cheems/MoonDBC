# MoonDBC

MoonDBC is a DBC parser and CAN signal codec toolkit written in MoonBit. It is intended for automotive gateways, battery-management systems, robotics, test benches, and browser-based diagnostic tools that need to turn raw CAN frames into named engineering values.

The current milestone provides a portable DBC data model, parsing for messages and signals, source-line diagnostics, and Intel/Motorola signal decoding. The parser recognizes `VERSION`, `BU_`, `BO_`, and `SG_` declarations, including byte order, signedness, scale, offset, range, unit, receivers, and multiplexing markers.

## Quick start

```moonbit
let source =
  #|BO_ 256 Powertrain: 8 ECU
  #| SG_ EngineSpeed : 0|16@1+ (0.125,0) [0|8000] "rpm" Dashboard
let result = @moondbc.parse(source)
if result.is_valid() {
  let message = result.database.find_message(256U).unwrap()
  let signal = message.find_signal("EngineSpeed").unwrap()
  let speed = signal.decode(b"\x40\x1f\x00\x00\x00\x00\x00\x00").unwrap()
  println("\{message.name}: \{speed} rpm")
}
```

Run the example and tests with the current MoonBit toolchain:

```text
moon run cmd/main
moon check --target wasm --deny-warn
moon test --target wasm --deny-warn
```

## Current scope

- typed models for databases, messages, signals, byte order, signedness, and multiplexing;
- parsing of core message and signal declarations;
- bit-accurate Intel and Motorola signal extraction across byte boundaries;
- signed value extension and factor/offset conversion;
- recoverable diagnostics for malformed and misplaced declarations;
- duplicate message and signal checks;
- portable library code for Wasm, Wasm-GC, JavaScript, and native targets.

## Roadmap

- signal encoding with physical/raw range checks;
- multiplexed message dispatch and value tables;
- DBC consistency checks and model comparison;
- MoonBit source generation from DBC models;
- native CLI and browser workbench.

## Project origin

MoonDBC is an original MoonBit implementation of the DBC data model and commonly documented text syntax. It does not copy source code from an existing DBC library. Any third-party compatibility fixtures added later will be recorded with their source and license.

## License

Apache-2.0.
