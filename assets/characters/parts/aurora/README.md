# Aurora modular placeholder

These files are intentionally simple, programmatic placeholder art. They are **not** slices, masks, or color samples from the old full-body portraits.

Regenerate from the repository root with:

```sh
python3 tools/draw_aurora_body_parts.py
```

The stage assembles nine semantic layers in this order:

1. `BACK`
2. `LEGS`
3. `SKIN`
4. `MILK` (breast/torso)
5. `HEART`
6. `HAIR`
7. `EYES`
8. `VOICE`
9. `HANDS`

Every file uses the same transparent 640×960 canvas so replacement art aligns without a manifest. `EYES` and `VOICE` have expression redraws under `expressions/<expression>/`; the other seven layers remain stable when Aurora changes expression.

## Replacement contract

- Keep the canvas at 640×960 with transparent background.
- Keep the visible part in the same location, or update its pivot in `aurora_modular_body.gd`.
- Export lossless RGBA WebP (`VP8L`), never PNG or opaque JPEG.
- Paint only the named region in each file. Do not restore full-body plates or masked copies.
- The runtime applies body shifts to the named layer only, so all nine layers must remain independent.
