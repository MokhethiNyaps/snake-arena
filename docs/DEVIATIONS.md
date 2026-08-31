# DEVIATIONS.md — CoilClash (Snake Arena)

Anything done differently from `MASTER_PROMPT_SNAKE_ARENA.md` and why.
Per the master prompt's precedence rules: if the document and the code ever
disagree, the document is right and the code is a bug — **unless** a
deviation is approved and logged here.

## Active deviations

*None so far.*

Phase 1 notes (choices the spec explicitly permits, recorded for clarity —
not deviations):

* Hand-rolled test runner instead of GUT: allowed by §9A ("Use GUT … or, if
  unavailable, a hand-rolled tests/run_tests.gd"). Decision #13.
* Engine 4.7.2 instead of 4.4/4.5: repo already declared 4.7 features; §0.2
  prefers the newest available. Decision #10.
* Jolt physics setting removed → default GodotPhysics3D (web-export
  compatibility). Decision #12.
