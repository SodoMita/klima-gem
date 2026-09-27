# The Klima Gem stage

The show is a real 3D studio built from Godot geometry — no painted backdrop —
and it lives inside the existing engine, so rollback, saves, the panic screen
and the story map all keep working. `scenes/show_stage/show_stage.gd` owns the
set and the choreography; `autoloads/show_director.gd` owns the show state and
hands the stage its cues; `dialogue/klima_gem_show.dialogue` is the script.

This document records the five rules the stage was rebuilt around, each of
which was a defect in the version first reviewed.

## 1. Compose for the frame the audience actually sees

The dialogue balloon covers the bottom of the picture. Anything the audience
has to read therefore has to land above it.

- **Camera** — `CAM_POS (0, 2.2, 9.4)`, `CAM_PITCH_DEG -8`, `CAM_FOV 45`:
  eye height in the front row, a longish lens, a small downward tilt. Applied
  in code from those constants (`_apply_camera`), so the number in the script
  is the number in the shot.
- **Bands** — the sign alone on the star cloth up top; the two word plaques
  flanking the stage at mid height; the gems and the altar centred below them;
  the trials on the platform in front.
- **Nothing crops** — there is no proscenium header or leg anywhere near the
  camera. The first build framed the set with a header at 3.78 m and legs at
  ±2.78 m, which put the header through the sign and the frame edges through
  the curtains.
- **Verified, not hoped** — `tests/stage_shot.sh` boots the real main scene
  under sway headless (pixman + llvmpipe), walks the show beat by beat, and
  for every shot projects the world AABB of the sign, the plaques, the gems,
  the chip, the star pips and the guest through the live camera. It prints the
  screen rectangle of each, draws them on the PNG, and flags anything that
  leaves the frame or crosses the balloon's top edge.

## 2. The throw is physics — and the stones decide the words

`project.godot` used to switch physics off entirely
(`physics/3d/physics_engine="Dummy"`). The gems were carried to their marks by
a tween. Now:

- `FlatTopGem` **is** a `RigidBody3D` with a convex-hull collider built from
  the diamond's own vertices.
- The platform, the altar head and a safety net far below the house floor are
  `StaticBody3D` with real collision shapes.
- `ShowStage._arc_velocity()` solves the ballistic problem for a given flight
  time, and `throw_gems(rng)` launches each gem with `throw_with_velocity()` —
  an impulse, gravity, spin from `angular_velocity`. It arcs, tumbles, bounces
  off the platform and comes to rest. `_wait_throw_rest()` watches the body
  from the stage; an epoch token cancels old flights when a rewind clears the
  gems, without resuming a coroutine on a deleted rigid body.
- Nothing is pre-rolled. The landing spot, flight time and spin come from the
  story RNG, and whatever face lands front-most — read with
  `front_face_for_azimuth()` — **is** the word. Only then does the show take
  over: `lift_to()` freezes the body, disables collisions so the stage cannot
  push a settled gem sideways, lifts it onto its mark keeping that face
  to the camera. That is choreography, and it says so.
- The two gems are on collision layer 2 with mask 1, i.e. they collide with
  the world and never with each other. Two hero props shoving each other off
  their marks is chaos, not drama.
- `throw_gems_fixed()` / `rethrow_gem_fixed()` exist only for tests and framing
  shots that need a specific word on camera. Gameplay never calls them.

`tests/stage_integrity_test.gd` asserts the engine is not `Dummy`, that a gem
is a rigid body with a hull, that a body launched upward rises and then falls
under gravity, and that a full physics-random throw reads two legal faces and
leaves both gems standing on their marks.

## 3. Every word is welded to the facet it names

The words are engraved on the eight slanted pavilion faces. In the first build
each label was roughly six times wider than the triangle it sat on, so all
eight overlapped into mush and none of them looked attached to anything.

- Each facet's true plane and outward normal come from its three mesh
  vertices (the pavilion normal points **down**, not up). The label lies in
  that plane, biased just 3 mm out to avoid depth fighting.
- The centre is 19% of the way from the girdle edge towards the apex: this
  reserves room for both the top and bottom of the word as the triangle
  narrows. `pixel_size` budgets **glyphs and their outline** in both axes;
  tests project all four corners of the ink rectangle into triangle
  barycentric coordinates and fail if even one falls outside the facet.
- The label's `+Z` axis points out of its facet, and `_fade_faces()` keeps
  the camera-facing facet visible. A reveal flashes the gem's emission,
  never doubles the text size and spills it onto neighbouring faces.
- `_fade_faces()` keeps only the face square to the camera. It measures by
  **azimuth**, not by a dot product: the pavilion normals lean downward, so a
  dot with a nearly level camera cannot reliably distinguish adjacent faces.
  A yaw of `+y` carries face azimuth `a` to `a - y`; using `+y` picked the
  neighbouring facet and put the wrong word in the light.
- `Label3D.outline_modulate` does **not** follow `modulate`'s alpha, so a
  hidden word still smeared its dark border across the facet. The outline is
  faded with the same alpha.

The readable presentation of a word is the plaque: a glowing copy that flies
out of the facet to the presentation slot beside the stage.

## 4. A colon inside dialogue text is `\:`

Dialogue Manager splits a line on the first `": "`. Unescaped, narration like

    A hush, and then the light finds it: a round stage...

promotes "A hush, and then the light finds it" to a **speaker name**, and the
balloon prints it as one. Every colon inside the text — narration and speech
alike — is written `\:`. `tests/stage_integrity_test.gd` lints the whole
dialogue file and fails on any unescaped one.

## 5. One sprite stands on the stage, and it is the guest

- Ren presents, but he is a voice on the microphone and is never rendered.
  `ShowDirector.enter_ren()` stands no portrait; it washes the key light over
  his mark instead.
- The guest is a single Y-billboard quad (MochiCow's `StageDirector`), parented
  to `World3D/Characters`.
- Two bugs kept her off the stage entirely: `characters_parent()` asked for
  `World3D/Characters` on a scene that never built `World3D`, and
  `ShowDirector._balloon()` looked for `VNBalloon` under `/root` when the
  balloon is parented to the current scene. Both are fixed, and the integrity
  test asserts exactly one portrait, under `World3D/Characters`, standing on
  her mark and inside the camera frame. Rewinds restore motion *before*
  GameState spawns Aurora; old quads and stage props detach immediately so
  repeated rewinds cannot create overlapping copies. The integrity test also
  rewinds repeatedly and interrupts a physical throw mid-flight.

## 6. You play AS Aurora; actions decide, words situate

- Aurora is the protagonist and the only portrait on the stage. Ren hosts —
  voice only, never rendered. Every choice is her action, and
  `GameState.player_name` is `"Aurora"`.
- Trial success has no dice. Each trial is decided by her **actions** (the
  stats her choices built) plus the gems' **situational edge**, against the
  trial number: trial 1 needs a total of 1, trial 2 needs 2, trial 3 needs 3.
  The Crossing tests bond + trust, Bell Barrage tests trust + power, the Echo
  Choir tests bond + insight. Same choices with the same words always clear or
  miss the same way.
- No word is generally good or bad. Every body part and every modification
  helps (+1) at least one trial and hinders (−1) at least one other; the edge
  columns sum to zero, so every trial is fair. A downside in one trial is an
  upside in another — read the board and play to it.
- The one crowd cheer still buys a re-throw of the modification gem, and the
  new word is whatever face the stones land on this time.

## Verifying by running

```bash
GODOT_BIN=/path/to/godot tests/show_stage_test.sh          # show logic, gems, trials, restore
GODOT_BIN=/path/to/godot tests/stage_integrity_test.sh     # the five rules above
GODOT_BIN=/path/to/godot tests/stage_shot.sh               # rendered framing (needs sway)
GODOT_BIN=/path/to/godot tests/run_headless.sh             # all of it
```

Shot output lands in `tests/render_samples/stage/`, and `stage_shot.gd` prints
the measured screen rectangle of everything the audience has to read, with the
balloon's top edge marked on every frame.
