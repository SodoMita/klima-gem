# Remaining-defect audit: async show state

Base: Aurora `76c9eca` (includes Caveman). Fix: `7daac8e` on
`fix/sam-klima-audit`. This branch deliberately does not duplicate Hugh's
stage/closed-box work, Aurora's story work, or Janitor's sprite/UI work.

## Fixed

The director previously resumed asynchronous work against whatever GameState
happened to exist when animation finished, even after rollback or loading.
An epoch invalidated by `sync_from_state()` or `begin_show()` now protects:

- Writing landed body/modification words after a throw.
- Writing the modification result after a reroll.
- Awarding a star after challenge animation.
- Clearing challenge props after the star flight.

Invalid/canceled face indices are rejected. Rerolls with no cheers do not
launch or spend currency. The reroll result has an explicit integer type:
the inherited inferred-type declaration failed Godot 4.7.2 import.

## Verification

`GODOT_BIN=/path/to/godot bash tests/show_async_state_test.sh`

Ten checks passed under Godot 4.7.2. Tests use a signal-controlled stage double
with the real autoload controller and `GameState.restore()`. This tests the
exact await boundaries, not timing-dependent sleeps. Includes normal throw
and challenge completion controls, not just cancellation checks.

Full `run_headless.sh`: import, runtime smoke, structural checks and motion
suite pass. Stops at show tests because three combo-specific lines use inline
condition markup that does not hide the line. Four dialogue branches still
reach END with legal star counts. Janitor's branch already contains the proper
block-condition repair; retain it when integrating Aurora's dialogue.

A separate show-suite run also failed an old fixed landing-position assertion
for the random modification gem (z 3.137 vs expected 3.3); a subsequent run
passed that assertion. Replace fixed target proximity with closed-box
containment and settled-body invariants during Hugh's physics integration.
Do not present the current full suite as green.

## Other remaining issues handed to owners

- Aurora: reroll choice is offered without checking `show_cheers > 0`.
  Controller now prevents overspending, but dialogue still needs a condition.
- Aurora: outlook compares score with zero while success compares score with
  trial number. A positive score can be advertised as advantage yet fail.
- Hugh: stage choreography still accesses `_pads` / `_stones` after waits.
  Restoring can clear or replace those arrays while old animation continues.
  The director guard prevents stale state commits, **not** scene-internal
  animation writes. Extend stage cancellation to the challenge choreography.
- Hugh owns visual verification, authored `.tscn`, closed throw box and
  integration of Janitor's face-label/sprite/rewind fixes. No rendered-stage
  verification is claimed for this controller-only branch.

## Integration

Cherry-pick the commits from this audit branch onto the combined stage branch.
Keep Janitor's additional actor cleanup in `sync_from_state()`, and keep the
new epoch increment at the start of that method. Preserve physics-returned
face results, not the older pre-rolled director implementation.
