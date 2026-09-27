# Klima gem

A Godot **4.7** game. The dialogue UI is the classical balloon from [vn_dialogue_demo](https://github.com/SodoMita/vn_dialogue_demo) (Nathan Hoad's Dialogue Manager), restyled for the Klima Gem show: translucent glass panels, cyan edges, per-speaker name colors, a stat strip, and a glass title card standing in front of the live 3D studio. Dialogic is not used.

Typewriter **sounds** are removed. Lines still reveal character by character; they do not tick.

Music is generated live, one score per background, by the SceneScore C extension. It is not a WAV and not a baked loop: a scene change crossfades two live scores, a `#music=` mood adjusts the score that is already playing, and `AudioDirector.reroll()` reseeds plucks that have not been scheduled yet. A classroom, the rift, the grove, and the lab do not share a track. If the library for this machine is missing, the GDScript mixer is the fallback.

## Getting started

1. Open this folder in **Godot 4.7**.
2. Press **F5**.

Main menu appears.

### Controls

- **Read on:** click, Enter, or Space. The first press finishes the text reveal; the next advances.
- **Skip:** hold Ctrl.
- **Close overlay:** Esc. Close is its own remappable binding, separate from Pause; with a menu open, Esc backs out instead of also pausing. Backspace stays free for number fields.
- **Log / rollback:** H, or the mouse wheel.
- **Quick save / load:** F5 / F9.
- **Pause:** Esc or right click.
- **Panic screen:** F12. Loads `scenes/panic_screen.tscn` — an opaque physics-lecture page you can redesign on its own — and silences every sound. Closing it (boss key again or the corner X) returns to the exact line, backlog place, stage dressing, and story state.
- **Story map:** a visited header rolls back. An unvisited header is replayed by Dialogue Manager so choices and mutations stay the engine's. A path that rewrites earlier choices waits for the spoiler toggle.

Save, load, settings, auto, and the story map live on the bottom system row.

### Display & settings notes

V-Sync is on by default. The toolbar Skip button latches; holding the Skip
key is momentary, and releasing it during a choice does not re-enable skip
after a response. Aurora remains the only on-stage portrait after rewinds,
loads and panic returns.

- Resolution presets and any custom size keep the 1280×720 layout and draw it at the window's pixel density, so the UI and sprites stay the same size without being stretched or blurred. The resolution row describes the window that is actually open — it follows a window-manager resize, a maximize and the Fullscreen checkbox — while the saved preference stays the size you last picked. A size the screen cannot show is fitted to the work area at the same aspect; a preset that cannot fit is greyed out, and a fit that happened is reported with a toast. Picking a size takes effect from a maximized or fullscreen window too (it returns to a plain window and unchecks Fullscreen), while a restored setting never fights one. The saved size is also applied to the title card at launch, so a restart does not look like the setting was forgotten. The panic page applies the same scale and — when it replaces the game — the saved rotation itself.
- Every slider except volume covers a wider range and is taller; UI scale and skip speed also have a number field beside the slider (the skip number is the delay in seconds; the slider still reads as speed, right is faster).
- In a portrait view the sprites are larger and set apart, and the speaking portrait stands in front of the other while staying behind the dialogue UI. A line that changes the speaker's expression brings their portrait forward even without a `#focus=` tag.
- Menus close with a press-and-hold on their empty space; the ring fills at your finger even when the UI is scaled or the view is rotated.

## Stage motion

Beyond `#bg=`/`#sprite=`/`#focus=`, the balloon carries a **StageDirector**
(`scenes/motion/stage_director.gd`): dialogue tags can tween any 2D/3D object
in the scene (`#tween=`, `#set=`), shake the stage (`#shake=`), and run
NLA-style animation tracks — crossfaded clips, loops and frame ranges on any
`AnimationPlayer`, state-machine travel on any `AnimationTree` (`#nla=`,
`#nla_track=`, `#nla_stop=`), and stand portraits in 3D scenes as quads that
face the camera by rotating only around the vertical axis (`#sprite3d=`,
placed by transform or by copying any 3D object — `#place3d=`). Aurora floats
on a `#tween=...?yoyo&loops=0` hover and the rift yanks the screen with
`#shake=stage`. Motion tags are
snapshotted into the backlog, so rollback and save slots put tweened objects
exactly where the story left them. Full tag grammar:
[docs/motion_director.md](docs/motion_director.md); headless suite:
`bash tests/motion_director_test.sh`.

## Layout

- `scenes/vn_balloon.tscn` — authored UI. Edit it in the Godot editor; the script does not build the chrome.
- `scenes/panic_screen.tscn` — the panic page, its own scene (`scenes/panic_screen.gd`), restyled here as a black lecture sheet; it can be redesigned without touching the balloon.
- `scenes/display_scale.gd` — shared window layout: the design canvas stays at the authored 1280×720 and larger windows render it with more pixels (never a window bigger than the screen).
- `dialogue/klima_gem_show.dialogue` — the booted story: the Klima Gem show. Stage tags: `#bg=`, `#sprite=key:left|right`, `#focus=`, `#music=`, `#sfx=`; show mutations resolve against the `ShowDirector` autoload.
- `scenes/show_stage/show_stage.tscn` + `show_stage.gd` — the 3D television studio, built procedurally from geometry; owns gems, the modification chip, trial props, star pips, stamps, confetti. The camera, the set and every prop are composed so the readable action lands above the dialogue balloon; `docs/show_stage.md` records the rules and the measurements.
- `scenes/show_stage/flat_top_gem.gd` — the Klima Gem itself: an octagonal-girdle diamond with a fully flat top and a word welded to every pavilion face. It is a `RigidBody3D`: the throw is an impulse, gravity, spin and a real landing, not a tween. Physics is therefore ON (`physics/3d/physics_engine="GodotPhysics3D"`); putting it back to `"Dummy"` makes the gems fall through the set.
- `scenes/motion/stage_director.gd` — the StageDirector: tweens, shakes and NLA tracks for any 2D/3D scene object, authored as the `MotionDirector` node in the balloon.
- `autoloads/game_state.gd` — trust, insight, power, bonds. Choices mutate these; rollback restores them.
- `Sprites/` — original portraits. `assets/characters/` — the same art, trimmed so it fits the left/right slots.
- `bgs/` — backgrounds, including the nexus still behind the title card.
- `addons/scene_score/` — live SceneScore mixer (C GDExtension). Source is in `native/scene_score/`.
- `addons/dialogue_manager/` — Dialogue Manager 4.1.0.

## The show stage

The booted story is the Klima Gem show, staged on a procedural 3D studio inside
the existing engine — rollback, saves, the panic screen and the story map all
keep working. Rules worth knowing before touching it:

- **Framing is measured.** `tests/stage_shot.sh` renders the real scene under
  sway headless and prints the projected screen rectangle of every piece the
  audience has to read, with the dialogue balloon's top edge drawn on each
  frame. Compose to that number, not to the editor camera.
- **The throw is physics.** The gems are `RigidBody3D`; the platform, the altar
  and a safety net are `StaticBody3D`. Gems collide with the world and never
  with each other.
- **Words are welded to facets**, sized to the triangle they sit on, and only
  the face square to the camera is lit. `_fade_faces()` measures by azimuth —
  the pavilion normals lean 44° up, so a dot product says every face is front.
- **A colon inside dialogue text is `\:`.** Dialogue Manager splits a line on
  the first `": "`, so an unescaped colon promotes narration to a speaker name.
  Both `tests/stage_integrity_test.sh` and the dialogue lint fail on one.
- **One sprite stands on this stage**, and it is the guest. Ren presents and is
  never rendered.

`docs/show_stage.md` has the full account, including the five defects this
stage was rebuilt around.

## Palette

The glass look lives on the balloon and the title card: navy panels around `Color(0.035, 0.045, 0.11, 0.8)`, cyan borders, and a soft blue shadow. Speaker names tint the name plate (Aurora cyan, Kira amber, Elara green, Selene violet).
