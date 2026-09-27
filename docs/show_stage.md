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

## 2. The throw is physics

`project.godot` used to switch physics off entirely
(`physics/3d/physics_engine="Dummy"`). The gems were carried to their marks by
a tween. Now:

- `FlatTopGem` **is** a `RigidBody3D` with a convex-hull collider built from
  the diamond's own vertices.
- The platform, the altar head and a safety net far below the house floor are
  `StaticBody3D` with real collision shapes.
- `ShowStage._arc_velocity()` solves the ballistic problem for a given flight
  time, and `throw_gems()` launches each gem with `throw_with_velocity()` — an
  impulse, gravity, spin from `angular_velocity`. It arcs, tumbles, bounces
  off the platform and comes to rest. `wait_until_rest()` watches the body
  until it settles.
- Only then does the show take over: `lift_to()` freezes the body, lifts it
  onto its mark and turns the rolled face to the camera. That is choreography,
  and it says so.
- The two gems are on collision layer 2 with mask 1, i.e. they collide with
  the world and never with each other. Two hero props shoving each other off
  their marks is chaos, not drama.

`tests/stage_integrity_test.gd` asserts the engine is not `Dummy`, that a gem
is a rigid body with a hull, that a body launched upward rises and then falls
under gravity, and that a full ceremonial throw leaves both gems standing on
their marks.

## 3. Every word is welded to the facet it names

The words are engraved on the eight slanted pavilion faces. In the first build
each label was roughly six times wider than the triangle it sat on, so all
eight overlapped into mush and none of them looked attached to anything.

- The label is placed at its facet's **centroid**, offset 6 mm along the
  facet's own outward normal, and tipped to the facet's slope.
- Its `pixel_size` is solved so the whole word fits inside the triangle
  (`WORD_FIT`, plus a height cap so short words do not grow).
- The label's `+Z` axis points out through the facet — the side `Label3D`
  draws its glyphs on — so the word is read, not mirrored, from outside.
- `_fade_faces()` keeps only the face square to the camera. It measures by
  **azimuth**, not by a dot product: the pavilion normals lean 44° up, so a dot
  with a nearly level camera never approaches 1 and every face looked "front".
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
  her mark and inside the camera frame.

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
