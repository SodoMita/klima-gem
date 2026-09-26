# Chrono Nexus (suxen-sonorhc)

A Godot **4.7** visual novel. The dialogue UI is the classical balloon from [vn_dialogue_demo](https://github.com/SodoMita/vn_dialogue_demo) (Nathan Hoad's Dialogue Manager), restyled for Chrono Nexus: translucent glass panels, cyan edges, per-speaker name colors, a stat strip, and a title card over the nexus still. Dialogic is not used.

Typewriter **sounds** are removed. Lines still reveal character by character; they do not tick.

Music is generated live, one score per background, by the SceneScore C extension. It is not a WAV and not a baked loop: a scene change crossfades two live scores, a `#music=` mood adjusts the score that is already playing, and `AudioDirector.reroll()` reseeds plucks that have not been scheduled yet. A classroom, the rift, the grove, and the lab do not share a track. If the library for this machine is missing, the GDScript mixer is the fallback.

## Getting started

1. Open this folder in **Godot 4.7**.
2. Press **F5**.

The title card sits on the nexus still. **Step through the rift** starts the short opening. **The long night** is the longer classroom prologue. **A flicker in the lab** is the Russian lab branch.

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
`#nla_track=`, `#nla_stop=`). Aurora floats on a `#tween=...?yoyo&loops=0`
hover and the rift yanks the screen with `#shake=stage`. Motion tags are
snapshotted into the backlog, so rollback and save slots put tweened objects
exactly where the story left them. Full tag grammar:
[docs/motion_director.md](docs/motion_director.md); headless suite:
`bash tests/motion_director_test.sh`.

## Layout

- `scenes/vn_balloon.tscn` — authored UI. Edit it in the Godot editor; the script does not build the chrome.
- `scenes/panic_screen.tscn` — the panic page, its own scene (`scenes/panic_screen.gd`), restyled here as a black lecture sheet; it can be redesigned without touching the balloon.
- `scenes/display_scale.gd` — shared window layout: the design canvas stays at the authored 1280×720 and larger windows render it with more pixels (never a window bigger than the screen).
- `dialogue/chrono_nexus.dialogue` — the story. Stage tags: `#bg=`, `#sprite=key:left|right`, `#focus=`, `#music=`, `#sfx=`, plus the motion tags (`#tween=`, `#set=`, `#shake=`, `#nla=`, `#target=`, `#nla_track=`) in docs/motion_director.md.
- `scenes/motion/stage_director.gd` — the StageDirector: tweens, shakes and NLA tracks for any 2D/3D scene object, authored as the `MotionDirector` node in the balloon.
- `autoloads/game_state.gd` — trust, insight, power, bonds. Choices mutate these; rollback restores them.
- `Sprites/` — original portraits. `assets/characters/` — the same art, trimmed so it fits the left/right slots.
- `bgs/` — backgrounds, including the nexus still behind the title card.
- `addons/scene_score/` — live SceneScore mixer (C GDExtension). Source is in `native/scene_score/`.
- `addons/dialogue_manager/` — Dialogue Manager 4.1.0.

## Palette

The glass look lives on the balloon and the title card: navy panels around `Color(0.035, 0.045, 0.11, 0.8)`, cyan borders, and a soft blue shadow. Speaker names tint the name plate (Aurora cyan, Kira amber, Elara green, Selene violet).
