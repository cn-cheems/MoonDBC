# opendbc compatibility fixture

`gm_global_a_chassis.dbc` and `gm_global_a_powertrain_expansion.dbc` are copied
from [`commaai/opendbc`](https://github.com/commaai/opendbc/tree/f1e707b7ad1ec807894ecc85149d8fd7ebb9649a/opendbc/dbc)
at commit `f1e707b7ad1ec807894ecc85149d8fd7ebb9649a`. Only line endings
and a final blank line have been normalized. They test real DBC attribute declarations,
multi-transmitter references, comments, and Intel/Motorola signals. The
upstream repository is MIT-licensed; its license notice is included in
`LICENSE`.

Both files are accepted by strict validation. The chassis file exercises
Motorola signal positions across byte boundaries; its rolling counter,
checksum, and command fields occupy distinct bits.
