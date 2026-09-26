# Stage motion director — tag reference

`scenes/motion/stage_director.gd` (`StageDirector`, authored as the
`MotionDirector` node inside `scenes/vn_balloon.tscn`) moves **any 2D or 3D
object in the running scene** and runs **NLA-style animation clips** straight
from dialogue tags. Like `#bg=` and `#sprite=`, motion tags are snapshotted
into the backlog, so rollback, the story map and save slots re-dress tweened
objects too.

Two grammar rules, imposed by Dialogue Manager's tag parser:

* **No commas inside a tag** — commas separate tags in `[...]`. Vector
  components are written with **spaces** (`position=640 360`), options are
  joined with **`&`**.
* **No `#` inside a tag** — it is stripped. Hex colors are written bare
  (`modulate=ff88cc`).

## Registering targets

```
[#target=crystal:BG3D/CrystalPivot]
[#nla_track=char:Characters/Aurora/AnimationPlayer]
```

`#target=` registers any node (Control, Node2D, Node3D, or anything with the
property you want to touch). `#nla_track=` registers an `AnimationPlayer`
**or** an `AnimationTree` as an animation track. Paths resolve against the
balloon, then the current scene, then the scene tree root; `%UniqueName`
works too. Register once — the alias sticks for the whole run.

Built-in aliases, ready without registration: `bg`, `left`, `right`, `box`,
`stage`.

Any tag can also name a raw NodePath instead of a registered alias
(`#tween=BG3D/CrystalPivot:rotation_degrees.y=90:1.0`); it is registered
automatically on first use.

## `#tween=` — move anything with an easing curve

```
#tween=<target>:<property>=<value>[:<duration>[:<transition>[:<ease>]]][?options]
```

```
[#tween=left:position=400 720:0.8:cubic:in_out]
[#tween=crystal:rotation_degrees.y=180:2.0:sine:in_out?delay=0.3]
[#tween=right:x=40:0.6?relative]
[#tween=bg:modulate=2244aa:1.2]
[#tween=box:alpha=0.0:0.4:quad:in]
```

| Field | Meaning |
|---|---|
| `property` | `position`, `x`, `y`, `z` (3D), `rotation` (degrees), `rx`/`ry`/`rz` (3D), `scale`, `sx`/`sy`/`sz`, `modulate`, `alpha`, `self_modulate`, `self_alpha`, `global_position`, `gx`/`gy`/`gz` — or any real property path with `.` instead of `:` (`mesh.material.albedo_color`) |
| `value` | number · `x y` · `x y z` · `x y z w` · hex color `rgb`/`rrggbb`/`rrggbbaa` |
| `duration` | seconds (default `0.5`; `0` or omitted with `?` opts = instant set) |
| `transition` | `linear` `sine` `quad` `cubic` `quart` `quint` `expo` `circ` `elastic` `back` `bounce` (default `quad`) |
| `ease` | `in` `out` `in_out` (default `out`) |

Options (after `?`, joined with `&`):

| Option | Meaning |
|---|---|
| `relative` | value is a delta added to the current value |
| `delay=S` | wait S seconds before starting |
| `speed=X` | divide the duration by X |
| `yoyo` | add a return step back to the start value |
| `loops=N` | repeat N times (`0` = forever; combine with `yoyo` for a hover) |

A new tween on the same target+property replaces the old one; tweens on
different properties coexist. `#tween_stop=<target>` kills everything running
on that target.

### Making slow motion read as smooth

Tweens step once per rendered frame with real deltas, so the curve itself is
frame-exact — but motion slower than roughly **0.25 px per frame** (≈15 px/s
at 60 fps) stops reading as movement and starts reading as shimmer: the
sprite blends between two pixel rows instead of sliding. For ambient loops
(hovers, breathing, drifting) keep the peak speed above that floor:

* amplitude ≥ ~12 px and/or half-period ≤ ~1.2 s — Aurora's hover is
  `position=0 -16:1.0:sine:in_out?relative&yoyo&loops=0` (peak ≈ 25 px/s);
* `sine:in_out` is the right shape for yoyo loops — it reaches zero velocity
  at both ends, so the turnaround has no kink;
* for effects that must stay sub-pixel-subtle, animate colour instead of
  position (`self_modulate`, `alpha`) — blending is per-pixel and always
  smooth;
* if even a large, fast tween stutters, it's frame pacing, not the tween:
  check the debugger's FPS/graphs (live SceneScore music and the typewriter
  both cost main-thread time), and leave `rendering/2d/snap_*` off — the
  project's `canvas_items` stretch + linear filtering already give smooth
  sub-pixel placement.

## `#set=` — instant, no curve

```
[#set=bg:modulate=ff2266]
[#set=crystal:visible=false]     (property paths beyond the shorthands work too)
```

Same property/value grammar as `#tween=`, supports `?relative`.

## `#shake=` — impact tremor

```
[#shake=stage:14:0.9]
[#shake=bg:6:0.9, #shake=left:12:0.8?rot]
```

`#shake=<target>[:<strength>[:<duration>]][?rot]` — decaying positional
noise that always lands exactly back on the origin. `?rot` adds a rotational
wobble. Shaking the whole `stage` reads as a camera shake.

## `#nla=` — NLA-style clips: crossfade, loops, frame ranges

Register AnimationPlayers as tracks, then treat each track like an NLA
track: playing a new clip **crossfades** out of the old one, and any clip can
be clamped to a **frame range**.

```
[#nla=char:idle?loop&blend=0.6]
[#nla=char:wave:10-45?fps=30&blend=0.3]
[#nla=door:open:0-20?fps=24&blend=0.2]
[#nla_stop=char]
```

`#nla=<track>:<clip>[:<FROM-TO>][?options]`

| Piece | Meaning |
|---|---|
| `FROM-TO` | frame range, e.g. `10-30`, `10-` (to the clip end), `-30` (from 0). Frames → seconds via `fps` |
| `blend=S` | crossfade seconds from whatever the track played before (default `0.2`) |
| `loop` | loop forever — inside the frame range if one is given, else re-trigger the clip when it ends |
| `speed=X` | playback rate |
| `fps=N` | frame rate for the range math (default `60`) |
| `hold` | (default) pause on the end frame, keeping the pose |
| `stop` | reset the pose instead of holding at the end frame |

Without a range, a non-looping clip plays to its own end. With a range and
no `loop`, playback pauses on the end frame. `#nla_stop=<track>` stops a
track immediately.

**AnimationTree tracks:** `#nla=<tree_track>:<state>` travels the state
machine to `<state>` instead. Range/blend/speed options don't apply — the
tree owns the blending.

**Layering:** several tracks can play at once (e.g. `body` + `face` players
animating disjoint bones) — each track keeps its own clip and range. For
weighted blending of clips that animate the *same* properties, register an
`AnimationTree` and let the engine blend.

## Rollback, saves and the panic screen

Every motion tag a line applies is stored on its backlog entry. Rolling back
(or loading a slot) calls `StageDirector.reset_all()` — every touched node
returns to the transform it had when first touched — and then replays the
recorded tags instantly, in story order. Net effect:

* absolute tweens/sets land exactly where the story left them;
* relative tweens re-accumulate the same deltas;
* NLA clips restart at their from-frame and keep looping;
* shakes and delays are transient and simply don't replay.

Two documented corners: a `?relative&yoyo&loops=0` hover replays as a single
offset (no floating until the line is shown live again), and the portrait
slots re-home whenever the layout re-dresses them (new texture, window
resize), which is what the layout wants anyway.

## From GDScript

```gdscript
var motion: StageDirector = %MotionDirector
motion.apply_tag("tween=left:position=640 360:0.5")
motion.reset_all()
motion.replay_tags(["tween=left:position=640 360:0.5"])
```

`tag_applied(tag)` / `tag_rejected(tag, reason)` signals are emitted for
every tag, which is how the balloon knows what to snapshot: rejected tags
(unknown target, bad property) are never recorded, so replay can't diverge
from what actually ran.

## Testing

`bash tests/motion_director_test.sh` (or `tests/run_headless.sh`, step 8)
runs the headless suite: tweens on 2D/3D/Control nodes, relative deltas,
instant sets, tween stop, NLA play/crossfade/stop, frame-range hold and
loop, state-machine travel, shake landing, delay/yoyo/loops, and rollback
replay.
