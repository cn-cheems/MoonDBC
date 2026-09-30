# Real CAN capture walkthrough

This exercise uses an externally hosted Nissan Leaf candump recording and its
companion DBC from [aphrx/canx](https://github.com/aphrx/canx/tree/7f37a3bf734b3fbcec0b52e99117466751315b5d).
The upstream README describes the log as real-car data. MoonDBC has verified
the file format and decoding results, not the circumstances of its capture.

The `canx` repository does not state a redistribution license. Its DBC and log
are **not included in MoonDBC**. Clone the pinned revision yourself to run this
exercise; do not treat the files as Apache-2.0 examples. MoonDBC's bundled
`fixtures/opendbc/` files are a separate, MIT-licensed source.

From the MoonDBC repository root, with Git, a current MoonBit toolchain and a
native C compiler installed:

```sh
git clone https://github.com/aphrx/canx.git ../MoonDBC-real-data
git -C ../MoonDBC-real-data checkout --detach 7f37a3bf734b3fbcec0b52e99117466751315b5d
moon run --target native cmd/moondbc -- check ../MoonDBC-real-data/nissan_leaf_2018.dbc
moon run --target native cmd/moondbc -- summary ../MoonDBC-real-data/nissan_leaf_2018.dbc ../MoonDBC-real-data/dumps/nissan_leaf_candump.log
```

At that revision, the DBC contains 18 messages and 130 signals. The summary
reported on 2026-09-30:

| Record outcome | Count |
| --- | ---: |
| Total nonblank records | 147,373 |
| Frames decoded | 18,381 |
| Signal values produced | 43,610 |
| IDs absent from this DBC | 117,273 |
| Frames shorter than the DBC definition | 11,719 |
| Malformed records or other decode failures | 0 |

`summary` returns status 1 because of short payloads. That status is useful:
the supplied DBC is not a complete, exact description of every bus frame in
the recording. Unknown IDs are counted separately and do not by themselves
cause failure. Do not claim that all signals in the drive were decoded or that
every decoded value is independently verified against vehicle instrumentation.

To inspect successfully decoded values, run `decode` with separate output and
diagnostic files:

```sh
moon run --target native cmd/moondbc -- decode ../MoonDBC-real-data/nissan_leaf_2018.dbc ../MoonDBC-real-data/dumps/nissan_leaf_candump.log > leaf-signals.csv 2> leaf-diagnostics.txt
```

The command returns status 1 for partial coverage but still writes the
successful signal rows. For example, frame `284#000000000000E86E` at log line
25 yields `WHEEL_SPEED_FR = 0 KPH`. The CSV preserves the capture timestamp,
interface, original line number and raw frame so a result can be traced back
to the recording. Inspect `leaf-diagnostics.txt` before using the exported
values for any engineering decision.
