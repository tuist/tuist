# Coverage test selection test bed

`golden.json` is the reference every coverage test selection step is checked against. Any change to `common/`, a variant or `scenarios.sh` must keep it in sync: see "Changing the fixture" in [README.md](README.md), and run `scenarios.sh check` on a fresh build. Keep scenario edits behavior-preserving so every selected test still passes, and keep the history deterministic.
