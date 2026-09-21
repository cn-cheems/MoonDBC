# MoonDBC

MoonDBC is a DBC parser and CAN signal codec toolkit written in MoonBit. It is intended for automotive gateways, battery-management systems, robotics, test benches, and browser-based diagnostic tools that need to turn raw CAN frames into named engineering values.

The current milestone provides a portable DBC data model, parsing for messages, signals, comments and value tables, source-line diagnostics, and Intel/Motorola signal encoding and decoding. The parser recognizes `VERSION`, `BU_`, `BO_`, `BO_TX_BU_`, `SG_`, `SIG_VALTYPE_`, `CM_`, and `VAL_` declarations, including standard and 29-bit extended frame identifiers, multiple transmitters, integer and IEEE-754 Float32/Float64 signals, byte order, signedness, scale, offset, range, unit, receivers, multiplexing markers, documentation comments, and enum labels.

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

For extended messages, `Message.id` preserves the bit-31 DBC identifier used by
cross-references. Use `Message::frame_id` and `Message::is_extended_frame` when
constructing or matching CAN bus frames.

Timestamped `candump` records can be decoded without preprocessing:

```moonbit
let trace = result.database.decode_trace(
  "(1697042645.123456) can0 100##1401F000000000000",
)
let csv = trace.to_csv().unwrap()
```

Source-aware parsing can drive bit-layout views and editors without adding
location fields to the semantic DBC model:

```moonbit
let parsed = @moondbc.parse_with_source_map(source)
let layout = parsed.analyze_frame_layout(256U).unwrap()
let first_bit = layout.find_cell(0, 0).unwrap()
for owner in first_bit.owners {
  println("\{owner.signal_name} bit \{owner.signal_bit}")
}
```

Each layout cell is classified as unused, singly occupied, shared by mutually
exclusive multiplex branches, or conflicting. Invalid and out-of-payload
signals retain their original declaration ranges in layout issues.

Run the example and tests with the current MoonBit toolchain:

```text
moon run cmd/main
moon run cmd/codegen
moon check --target wasm --deny-warn
moon test --target wasm --deny-warn
```

## Browser workbench

MoonDBC includes a local browser workbench for inspecting DBC source, parser
diagnostics, messages, signals, and source-aware CAN frame layouts. Parsing runs
in the browser; the DBC text is not uploaded anywhere.

```text
moon install moonbit-community/warren
warren dev --browser-entry workbench
```

Open the local URL printed by Warren. The workbench starts with a multiplexed
sample and accepts pasted DBC text in the source editor.

Inspect a real DBC file with the native command-line tool:

```text
moon run --target native cmd/moondbc -- check examples/vehicle.dbc
moon run --target native cmd/moondbc -- list examples/vehicle.dbc
moon run --target native cmd/moondbc -- decode examples/vehicle.dbc examples/vehicle.log
moon run --target native cmd/moondbc -- encode examples/vehicle.dbc 100 EngineSpeed=1000 CoolantTemp=85 Gear=1
moon run --target native cmd/moondbc -- format examples/vehicle.dbc
moon run --target native cmd/moondbc -- format --check examples/vehicle.dbc
moon run --target native cmd/moondbc -- diff examples/vehicle.dbc examples/vehicle-v2.dbc
moon run --target native cmd/moondbc -- generate examples/vehicle.dbc > vehicle_constants.mbt
```

`encode` accepts a hexadecimal bus identifier followed by one or more
`NAME=NUMBER` physical signal assignments. Use one to three identifier digits
for a standard frame and pad to at least four digits for an extended frame.

`format` writes a deterministic DBC representation to standard output. Its
`--check` mode produces no output when the file is canonical and exits with
status `4` when formatting changes are required, making it suitable for CI.
Declarations outside the currently supported syntax are rejected rather than
silently removed.

`diff` writes a Markdown compatibility report. It exits with status `3` when
breaking changes are present, so the command can act as a CI compatibility gate.

## Current scope

- typed models for databases, messages, signals, byte order, signedness, and multiplexing;
- parsing of core message and signal declarations;
- deferred resolution of `VAL_` value descriptions and label lookup;
- database, node, message, and signal `CM_` comments with reference validation;
- multi-transmitter messages through deferred `BO_TX_BU_` resolution;
- bit-31 DBC extended-frame identifiers with collision-safe SocketCAN lookup;
- bit-accurate Intel and Motorola signal extraction across byte boundaries;
- signed value extension and factor/offset conversion;
- IEEE-754 Float32 and Float64 decoding and encoding through `SIG_VALTYPE_` declarations;
- raw and physical signal encoding without mutating the input payload;
- type, width, frame, scale, and physical range validation;
- message-level frame decoding with multiplex selector dispatch;
- message-level frame encoding from strict named signal assignments;
- automatic enrichment of decoded values with `VAL_` labels;
- semantic validation for frame bounds, overlaps, scaling, and multiplexing;
- source-aware CAN payload layout analysis with multiplex sharing and conflict classification;
- deterministic model comparison for messages, signals, and value tables;
- compatibility impact classification and deterministic Markdown change reports;
- standalone MoonBit constant generation for static CAN metadata;
- deterministic DBC export with parse-write-parse round-trip support;
- Classical CAN and CAN FD SocketCAN/candump parsing, formatting, and direct decoding;
- recoverable multi-frame trace decoding and CSV signal export;
- recoverable diagnostics for malformed and misplaced declarations;
- native `check`, `list`, trace-to-CSV `decode`, physical-value `encode`, deterministic `format`, compatibility `diff`, and MoonBit `generate` commands;
- duplicate message and signal checks;
- portable library code for Wasm, Wasm-GC, JavaScript, and native targets.

## Project origin

MoonDBC is an original MoonBit implementation of the DBC data model and commonly documented text syntax. It does not copy source code from an existing DBC library. Any third-party compatibility fixtures added later will be recorded with their source and license.

## License

Apache-2.0.
