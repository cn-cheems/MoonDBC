# MoonDBC: five-minute demonstration

These commands run from the repository root. Use a current MoonBit toolchain
on Linux, macOS, or Windows with a C compiler (WSL with GCC also works).
Start with `moon update` after cloning.

## 1. Validate a real DBC

```text
moon run --target native cmd/moondbc -- check fixtures/opendbc/gm_global_a_chassis.dbc
```

The command reports `OK`, 4 messages, 9 signals and 5 nodes. This fixture
comes from commaai/opendbc; its exact upstream revision and MIT license are
recorded in [fixtures/opendbc/README.md](../fixtures/opendbc/README.md).

## 2. Turn a CAN log into physical values

```text
moon run --target native cmd/moondbc -- decode examples/vehicle.dbc examples/vehicle.log
```

The CSV includes a timestamp, interface, frame, message and named signal. In
the first frame, EngineSpeed is 1000 rpm and Gear is labelled `Drive`. The log
also contains an extended CAN frame and an IEEE-754 floating-point signal.

## 3. Detect a breaking DBC change

```text
moon run --target native cmd/moondbc -- diff examples/vehicle.dbc examples/vehicle-v2.dbc
```

The Markdown report identifies one breaking signal modification, one
non-breaking addition and one informational version change, with old and new
source lines. The command exits nonzero because of the breaking change, so it
can be used as a CI gate.

## 4. Inspect and decode locally in a browser

```text
moon install moonbit-community/warren
warren dev --browser-entry workbench
```

Open the local URL printed by Warren. The built-in DBC and frame
`100#401F7D0100000000` show 2000 rpm, 85 degC and gear 1. Paste another
SocketCAN frame or timestamped candump record to see active signal values;
change the DBC to inspect bit layout and source-located diagnostics. If the
Warren installer reports no system C compiler, run it under WSL with GCC or
install a compatible compiler.

No CAN hardware, private service or uploaded vehicle data is required.
