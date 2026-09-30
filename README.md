# MoonDBC

MoonDBC is a DBC parser and CAN signal codec toolkit written in MoonBit. It is intended for automotive gateways, battery-management systems, robotics, test benches, and browser-based diagnostic tools that need to turn raw CAN frames into named engineering values.

The current milestone provides a portable DBC data model, parsing for messages, signals, signal groups, comments, attributes and value tables, source-line diagnostics, and Intel/Motorola signal encoding and decoding. The parser recognizes `VERSION`, `BU_`, `BO_`, `BO_TX_BU_`, `SG_`, `SG_MUL_VAL_`, `SIG_GROUP_`, `SIG_VALTYPE_`, `CM_`, `BA_DEF_`, `BA_DEF_DEF_`, `BA_`, and `VAL_` declarations, including standard and 29-bit extended frame identifiers, multiple transmitters, integer and IEEE-754 Float32/Float64 signals, byte order, signedness, scale, offset, range, unit, receivers, basic and range-based single-selector multiplexing, named signal groups, documentation comments, scoped attributes, and enum labels. `NS_` namespace listings and an empty `BS_:` header are accepted as structural metadata. Other declarations are reported as unsupported instead of silently discarded; relationship attributes and nested/multiple-selector multiplexing are not implemented.

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
location fields to the semantic DBC model. Message, signal, and comment
declarations are available through the source map:

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
`parsed.locate_validation_issues()` also attaches source ranges to semantic
failures such as overlapping signals; issues without a retained declaration
location explicitly report no source range.
For two parsed revisions, `before.diff_with_locations(after)` pairs each
structural change with the old and new declaration ranges, including `VAL_`
value tables.

Run the example and tests with the current MoonBit toolchain:

```text
moon run cmd/main
moon run cmd/codegen
moon check --target wasm --deny-warn
moon test --target wasm --deny-warn
```

## Browser workbench

MoonDBC includes a local browser workbench for inspecting DBC source, parser
and semantic diagnostics, messages, signals, and source-aware CAN frame layouts. Parsing runs
in the browser; the DBC text is not uploaded anywhere.

```text
moon install moonbit-community/warren
warren dev --browser-entry workbench
```

Open the local URL printed by Warren. The workbench starts with a multiplexed
sample and accepts pasted DBC text or local `.dbc` files up to 4 MiB. Imported
files stay in the browser and are not uploaded.

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
moon run --target native cmd/moondbc -- generate-codecs examples/vehicle.dbc > vehicle_codecs.mbt
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
Each changed message, signal, comment, or value table includes its old and/or
new declaration line in the report.
All CLI commands that validate a DBC include source line and column for
locatable semantic errors, so malformed layouts can be found directly from CI
output.

The [extended multiplexing example](examples/extended-multiplex.dbc) uses
`SG_MUL_VAL_` to activate the same signal in multiple selector ranges. Those
ranges are used consistently by frame encoding, decoding, overlap validation,
layout analysis, deterministic DBC writing, and generated metadata. This
milestone supports one multiplexer per message; nested or independent selector
trees require a different model and are not claimed as supported.
Selector values in the current public model are nonnegative 32-bit `Int` values.

Attribute definitions, defaults, and explicit assignments are retained in
`Database.attributes`. `Database::attribute_value` resolves an explicit value
or the definition's default for an existing database, node, message, or signal
target. Supported attribute types are `INT`, `HEX`, `FLOAT`, `STRING`, and
`ENUM`. The strict parser rejects unknown references, scope mismatches, and
unsupported attribute syntax instead of dropping metadata. The
[pinned opendbc fixtures](fixtures/opendbc/README.md) exercise these paths
against real vehicle DBC files; the upstream MIT notice is included there.

`generate-codecs` emits named MoonBit encode and decode functions for each
signal. The destination package must import `cn-cheems/moondbc` as `@moondbc`.
The functions do not parse DBC text at runtime and operate on individual
signals; use the existing frame API for multiplex branch selection. The
checked-in [generated codec example](examples/generated/generated.mbt) is
compiled and tested on the supported targets.

## Current scope

- typed models for databases, messages, signals, byte order, signedness, and multiplexing;
- parsing of core message and signal declarations;
- deferred resolution of `VAL_` value descriptions and label lookup;
- named `SIG_GROUP_` metadata with reference validation, lookup, and deterministic export;
- database, node, message, and signal `CM_` comments with reference validation;
- scoped DBC attribute definitions, defaults, assignments, lookup, and deterministic export;
- multi-transmitter messages through deferred `BO_TX_BU_` resolution;
- bit-31 DBC extended-frame identifiers with collision-safe SocketCAN lookup;
- bit-accurate Intel and Motorola signal extraction across byte boundaries;
- signed value extension and factor/offset conversion;
- IEEE-754 Float32 and Float64 decoding and encoding through `SIG_VALTYPE_` declarations;
- raw and physical signal encoding without mutating the input payload;
- type, width, frame, scale, and physical range validation;
- message-level frame decoding with multiplex selector dispatch;
- inclusive, discontiguous `SG_MUL_VAL_` selector ranges with deferred reference resolution;
- message-level frame encoding from strict named signal assignments;
- automatic enrichment of decoded values with `VAL_` labels;
- semantic validation for frame bounds, overlaps, scaling, and multiplexing;
- source-aware CAN payload layout analysis with multiplex sharing and conflict classification;
- deterministic model comparison for messages, signals, and value tables;
- compatibility impact classification and deterministic Markdown change reports;
- standalone MoonBit constant generation for static CAN metadata;
- named, statically configured MoonBit signal codec generation;
- deterministic DBC export with parse-write-parse round-trip support;
- Classical CAN and CAN FD SocketCAN/candump parsing, formatting, and direct decoding;
- recoverable multi-frame trace decoding and CSV signal export;
- recoverable diagnostics for malformed and misplaced declarations;
- native `check`, `list`, trace-to-CSV `decode`, physical-value `encode`, deterministic `format`, compatibility `diff`, `generate`, and `generate-codecs` commands;
- duplicate message and signal checks;
- portable library code for Wasm, Wasm-GC, JavaScript, and native targets.

## Project origin

MoonDBC is an original MoonBit implementation of the DBC data model and commonly documented text syntax. It does not copy source code from an existing DBC library. The third-party DBC fixtures are credited with their source and license in their own directory.

## License

Apache-2.0.
