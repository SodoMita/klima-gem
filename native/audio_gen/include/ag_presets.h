#ifndef AG_PRESETS_H
#define AG_PRESETS_H

#include "ag_common.h"
#include "ag_sfx.h"
#include "ag_drums.h"
#include "ag_proc_music.h"

#ifdef __cplusplus
extern "C" {
#endif

/* High-level game audio presets - one-liners for common game sounds.
 * These are convenience wrappers that fill AgSfxParams or render directly.
 * Designed for future use in Chrono Nexus and other games.
 */

/* UI */
void ag_preset_ui_click(AgSfxParams *out);
void ag_preset_ui_hover(AgSfxParams *out);
void ag_preset_ui_confirm(AgSfxParams *out);
void ag_preset_ui_back(AgSfxParams *out);
void ag_preset_ui_error(AgSfxParams *out);
void ag_preset_ui_save(AgSfxParams *out);
void ag_preset_ui_open(AgSfxParams *out);
void ag_preset_ui_close(AgSfxParams *out);

/* Gameplay */
void ag_preset_footstep(AgSfxParams *out, int surface); /* 0=grass,1=stone,2=wood,3=metal */
void ag_preset_jump(AgSfxParams *out);
void ag_preset_land(AgSfxParams *out);
void ag_preset_pickup(AgSfxParams *out, int type); /* 0=coin,1=powerup,2=key */
void ag_preset_hit(AgSfxParams *out, int hard); /* 0=soft,1=hard */
void ag_preset_explosion(AgSfxParams *out, int size); /* 0=small,1=med,2=large */
void ag_preset_laser(AgSfxParams *out, int type);
void ag_preset_whoosh(AgSfxParams *out);
void ag_preset_teleport(AgSfxParams *out);
void ag_preset_heal(AgSfxParams *out);
void ag_preset_levelup(AgSfxParams *out);

/* Ambient one-shots */
void ag_preset_wind_gust(AgSfxParams *out);
void ag_preset_rain_drop(AgSfxParams *out);
void ag_preset_thunder(AgSfxParams *out);

/* Music specs for scenes - like THEMES but more */
void ag_preset_music_for_scene(const char *scene_name, AgProcSpec *out, uint64_t seed);
void ag_preset_music_for_mood(const char *mood_name, AgProcSpec *out, uint64_t seed);

/* Drum patterns */
void ag_preset_drum_pattern_basic(AgDrumPattern *out, float bpm);
void ag_preset_drum_pattern_lofi(AgDrumPattern *out, float bpm);
void ag_preset_drum_pattern_techno(AgDrumPattern *out, float bpm);
void ag_preset_drum_pattern_ambient(AgDrumPattern *out, float bpm);

#ifdef __cplusplus
}
#endif

#endif
