# Fix log

## 2026-11-17 Hikaru games said "BIOS set hikaru.zip missing"

Symptom: Verify Games marked all six Hikaru games Incomplete with "MAME 0.289: BIOS set hikaru.zip missing", though hikaru.zip, with every BIOS chip, was in BIOS/mame/bios.
Cause: the MAME list reader dropped every chip tagged `bios="…"` (the BIOS versions), so the only chips left to stand for the BIOS set were the EEPROMs' default contents (93c46.ic115, x76f100.ic85), which BIOS zips rarely carry. None found meant "BIOS set missing".
Fix: `ArcadeVerifier`'s reader keeps BIOS-version chips, marked `biosChoice`; when a game lists them, any one present means the BIOS is there. The rebuilder treats them as BIOS chips too, and the cache name changed so older lists are read again.
Rule: When a list marks alternatives ("any one of these"), keep them and test for one of them; never drop them and judge by whatever chips are left, which may be optional ones.
