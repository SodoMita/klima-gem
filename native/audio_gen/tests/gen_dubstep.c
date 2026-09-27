/* Renders the dubstep engine + every event one-shot to /tmp and self-checks
 * that each one is audible, finite and not clipped to death.
 * Build: see build.sh (bin/gen_dubstep). */

#include "ag_dubstep.h"
#include "ag_wav.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int fails = 0;
static int checks = 0;

static void check(int cond, const char *what) {
    checks++;
    if (!cond) { fails++; printf("  FAIL %s\n", what); }
}

static float peak_of(const float *b, int n) {
    float p = 0.0f; int i;
    for (i = 0; i < n; i++) { float a = fabsf(b[i]); if (a > p) p = a; }
    return p;
}

static float rms_of(const float *b, int n) {
    double s = 0.0; int i;
    for (i = 0; i < n; i++) s += (double)b[i] * (double)b[i];
    return (float)sqrt(s / (n > 0 ? n : 1));
}

static int finite_all(const float *b, int n) {
    int i;
    for (i = 0; i < n; i++) if (!(b[i] == b[i]) || fabsf(b[i]) > 8.0f) return 0;
    return 1;
}

int main(void) {
    const int sr = 44100;
    int k;
    char path[256];
    float *buf = (float *)malloc(sizeof(float) * sr * 40 * 2);
    if (!buf) return 1;

    printf("== dubstep one-shots (%d kinds) ==\n", AG_DUB_SFX_COUNT);
    for (k = 0; k < AG_DUB_SFX_COUNT; k++) {
        int n = ag_dub_sfx_render(k, 0.8f, 0, buf, sr * 4, sr);
        float p = peak_of(buf, n), rms = rms_of(buf, n);
        printf("  %-14s frames=%6d peak=%.3f rms=%.4f\n", ag_dub_sfx_name(k), n, p, rms);
        check(n > 100, "one-shot length");
        check(finite_all(buf, n), "one-shot finite");
        check(p > 0.02f, "one-shot audible");
        check(p <= 1.5f, "one-shot not exploding");
        snprintf(path, sizeof(path), "/tmp/ag_dub_%s.wav", ag_dub_sfx_name(k));
        ag_wav_write_f32(path, buf, n, 1, sr);
    }

    printf("== determinism ==\n");
    {
        float *a = (float *)malloc(sizeof(float) * sr);
        int n1 = ag_dub_sfx_render(AG_DUB_SFX_GEM_HIT, 0.5f, 42, a, sr, sr);
        int n2 = ag_dub_sfx_render(AG_DUB_SFX_GEM_HIT, 0.5f, 42, buf, sr, sr);
        int same = (n1 == n2) && memcmp(a, buf, sizeof(float) * n1) == 0;
        check(same, "same seed -> same samples");
        n2 = ag_dub_sfx_render(AG_DUB_SFX_GEM_HIT, 0.5f, 43, buf, sr, sr);
        check(memcmp(a, buf, sizeof(float) * n1) != 0, "other seed -> other samples");
        free(a);
    }

    printf("== energy scaling ==\n");
    {
        int n = ag_dub_sfx_render(AG_DUB_SFX_GEM_HIT, 0.1f, 7, buf, sr, sr);
        float soft = peak_of(buf, n);
        n = ag_dub_sfx_render(AG_DUB_SFX_GEM_HIT, 1.0f, 7, buf, sr, sr);
        check(peak_of(buf, n) > soft * 1.3f, "hard gem hit is louder than soft");
    }

    printf("== variants check ==\n");
    for (int v = 0; v < AG_DUB_VARIANT_COUNT; v++) {
        AgDubstep d;
        ag_dubstep_init(&d, sr, v, 0.0, 100 + v);
        ag_dubstep_set_gain(&d, 1.0f, 0.05f);
        ag_dubstep_set_intensity(&d, 0.8f, 0.05f);
        ag_dubstep_render(&d, buf, sr * 2);
        float p = peak_of(buf, sr * 4);
        float r = rms_of(buf, sr * 4);
        printf("  variant %d (bpm=%.1f root=%d): peak=%.3f rms=%.4f\n", v, d.bpm, d.root, p, r);
        check(p > 0.05f, "variant audible");
        check(finite_all(buf, sr * 4), "variant finite");
    }

    printf("== dynamic switching check ==\n");
    {
        AgDubstep d;
        ag_dubstep_init(&d, sr, AG_DUB_VARIANT_SUSPENSE, 135.0, 42);
        ag_dubstep_set_gain(&d, 1.0f, 0.05f);
        ag_dubstep_set_intensity(&d, 0.6f, 0.05f);
        ag_dubstep_render(&d, buf, sr); // 1 gem rolling suspense
        check(d.variant == AG_DUB_VARIANT_SUSPENSE, "starts suspense");

        ag_dubstep_switch_mode(&d, AG_DUB_VARIANT_GROOVE, 0.95f, 0.2f);
        ag_dubstep_event(&d, AG_DUB_EV_DROP); // both gems placed: drop
        ag_dubstep_render(&d, buf + sr * 2, sr);
        check(d.variant == AG_DUB_VARIANT_GROOVE, "switched to groove");

        ag_dubstep_switch_mode(&d, AG_DUB_VARIANT_VICTORY, 1.0f, 0.1f);
        ag_dubstep_render(&d, buf + sr * 4, sr);
        check(d.variant == AG_DUB_VARIANT_VICTORY, "switched to victory");

        ag_dubstep_switch_mode(&d, AG_DUB_VARIANT_DEFEAT, 0.4f, 0.1f);
        ag_dubstep_render(&d, buf + sr * 6, sr);
        check(d.variant == AG_DUB_VARIANT_DEFEAT, "switched to defeat");
    }

    printf("== live engine ==\n");
    {
        AgDubstep d;
        int frames = sr * 24;
        int i;
        ag_dubstep_init(&d, sr, AG_DUB_VARIANT_STAGE, 140.0, 20260927);
        ag_dubstep_set_gain(&d, 1.0f, 0.4f);
        ag_dubstep_set_intensity(&d, 0.6f, 0.5f);
        for (i = 0; i < 6; i++) ag_dubstep_render(&d, buf + i * sr * 2, sr);
        ag_dubstep_event(&d, AG_DUB_EV_RISER);
        for (i = 6; i < 12; i++) ag_dubstep_render(&d, buf + i * sr * 2, sr);
        ag_dubstep_trigger_sfx(&d, AG_DUB_SFX_GEM_HIT, 0.9f, -0.4f, 0.9f);
        ag_dubstep_event(&d, AG_DUB_EV_FILL);
        for (i = 12; i < 16; i++) ag_dubstep_render(&d, buf + i * sr * 2, sr);
        ag_dubstep_set_variant(&d, AG_DUB_VARIANT_TRIAL, 150.0);
        ag_dubstep_set_intensity(&d, 1.0f, 0.3f);
        for (i = 16; i < 20; i++) ag_dubstep_render(&d, buf + i * sr * 2, sr);
        ag_dubstep_event(&d, AG_DUB_EV_BREAK);
        ag_dubstep_release(&d, 1.5f);
        for (i = 20; i < 24; i++) ag_dubstep_render(&d, buf + i * sr * 2, sr);

        printf("  steps=%d kicks=%d snares=%d events=%d peak=%.3f rms=%.4f\n",
               d.steps_played, d.hits_kick, d.hits_snare, d.events_fired,
               peak_of(buf, frames * 2), rms_of(buf, frames * 2));
        check(finite_all(buf, frames * 2), "engine output finite");
        check(peak_of(buf, frames * 2) > 0.2f, "engine is loud enough");
        check(peak_of(buf, frames * 2) <= 1.05f, "engine stays inside 0 dBFS");
        check(rms_of(buf, frames * 2) > 0.03f, "engine has body");
        check(d.steps_played > 200, "transport advanced");
        check(d.hits_kick > 30, "kicks placed");
        check(d.hits_snare > 10, "snares placed");
        check(!ag_dubstep_active(&d), "released engine goes silent");
        ag_wav_write_f32("/tmp/ag_dubstep_stage.wav", buf, frames, 2, sr);
    }

    printf("== intensity floor ==\n");
    {
        AgDubstep d;
        float quiet, loud;
        ag_dubstep_init(&d, sr, AG_DUB_VARIANT_CHILL, 128.0, 5);
        ag_dubstep_set_gain(&d, 1.0f, 0.05f);
        ag_dubstep_set_intensity(&d, 0.05f, 0.05f);
        ag_dubstep_render(&d, buf, sr * 4);
        quiet = rms_of(buf, sr * 8);
        ag_dubstep_set_intensity(&d, 1.0f, 0.05f);
        ag_dubstep_render(&d, buf, sr * 4);
        loud = rms_of(buf, sr * 8);
        printf("  quiet rms=%.4f loud rms=%.4f\n", quiet, loud);
        check(loud > quiet * 1.25f, "intensity raises the mix");
    }

    free(buf);
    printf("\n%d checks, %d failures\n", checks, fails);
    return fails ? 1 : 0;
}
