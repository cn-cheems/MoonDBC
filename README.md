# MoonDBC

MoonDBC is a DBC parser and CAN signal codec toolkit written in MoonBit. It is intended for automotive gateways, battery-management systems, robotics, test benches, and browser-based diagnostic tools that need to turn raw CAN frames into named engineering values.

The current milestone provides a portable DBC data model, parsing for messages, signals, comments and value tables, source-line diagnostics, and Intel/Motorola signal encoding and decoding. The parser recognizes `VERSION`, `BU_`, `BO_`, `BO_TX_BU_`, `SG_`, `CM_`, and `VAL_` declarations, including multiple transmitters, byte order, signedness, scale, offset, range, unit, receivers, multiplexing markers, documentation comments, and enum labels.

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

Timestamped `candump` records can be decoded without preprocessing:

```moonbit
let trace = result.database.decode_trace(
  "(1697042645.123456) can0 100##1401F000000000000",
)
let csv = trace.to_csv().unwrap()
```

Run the example and tests with the current MoonBit toolchain:

```text
moon run cmd/main
moon run cmd/codegen
moon check --target wasm --deny-warn
moon test --target wasm --deny-warn
```

## Current scope

- typed models for databases, messages, signals, byte order, signedness, and multiplexing;
- parsing of core message and signal declarations;
- deferred resolution of `VAL_` value descriptions and label lookup;
- database, node, message, and signal `CM_` comments with reference validation;
- multi-transmitter messages through deferred `BO_TX_BU_` resolution;
- bit-accurate Intel and Motorola signal extraction across byte boundaries;
- signed value extension and factor/offset conversion;
- raw and physical signal encoding without mutating the input payload;
- type, width, frame, scale, and physical range validation;
- message-level frame decoding with multiplex selector dispatch;
- message-level frame encoding from strict named signal assignments;
- automatic enrichment of decoded values with `VAL_` labels;
- semantic validation for frame bounds, overlaps, scaling, and multiplexing;
- deterministic model comparison for messages, signals, and value tables;
- compatibility impact classification and deterministic Markdown change reports;
- standalone MoonBit constant generation for static CAN metadata;
- deterministic DBC export with parse-write-parse round-trip support;
- Classical CAN and CAN FD SocketCAN/candump parsing, formatting, and direct decoding;
- recoverable multi-frame trace decoding and CSV signal export;
- recoverable diagnostics for malformed and misplaced declarations;
- duplicate message and signal checks;
- portable library code for Wasm, Wasm-GC, JavaScript, and native targets.

## Roadmap

- native CLI and browser workbench.

## Project origin

MoonDBC is an original MoonBit implementation of the DBC data model and commonly documented text syntax. It does not copy source code from an existing DBC library. Any third-party compatibility fixtures added later will be recorded with their source and license.

## License

Apache-2.0.
