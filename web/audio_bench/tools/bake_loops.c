/* bake_loops.c - Klima Gem web audio bake tool (agent gem-dev-16-miku-9v2)
 *
 * The web export ships gdextensionLibs:[] so the AudioGen C engine never
 * loads and the game falls back to a per-sample GDScript pump at 22050 Hz.
 * Human directive: no GDScript audio, use the real C engine, 48000 Hz.
 *
 * This tool renders the REAL ag_dubstep.c engine offline into 48 kHz WAV
 * loops + one-shots that the web build can stream without any script-side
 * synthesis. Same DSP the GDExtension runs natively.
 *
 * build:  cc -O2 -std=c99 -I../../native/audio_gen/include \
 *              bake_loops.c ../../native/audio_gen/src/ag_dubstep.c \
 *              ../../native/audio_gen/src/ag_common.c -lm -o bake_loops
 * run:    ./bake_loops /path/to/public/audio
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

#include "ag_dubstep.h"

#define SR 48000          /* human directive: 48 kHz */
#define BPM 120.0         /* 1 bar = 2.0 s = 96000 frames exactly at 48k */
#define BARS 2
#define SEED 0x9E7ULL

typedef struct { const char *name; int variant; const char *label; } VariantSpec;

static const VariantSpec VARIANTS[] = {
    { "stage",    AG_DUB_VARIANT_STAGE,    "game-show floor: driving mid wobble" },
    { "trial",    AG_DUB_VARIANT_TRIAL,    "challenge running: faster, tense" },
    { "chill",    AG_DUB_VARIANT_CHILL,    "half-speed, filtered, between rounds" },
    { "suspense", AG_DUB_VARIANT_SUSPENSE, "one gem rolling: heartbeat sub" },
    { "groove",   AG_DUB_VARIANT_GROOVE,   "both gems placed: peak drop groove" },
    { "victory",  AG_DUB_VARIANT_VICTORY,  "triumphant arps over the wobble" },
    { "defeat",   AG_DUB_VARIANT_DEFEAT,   "dark sub decay" },
};

typedef struct { const char *name; int kind; } SfxSpec;

static const SfxSpec SFX[] = {
    { "gem_hit",   AG_DUB_SFX_GEM_HIT },
    { "gem_land",  AG_DUB_SFX_GEM_LAND },
    { "gem_spawn", AG_DUB_SFX_GEM_SPAWN },
    { "throw",     AG_DUB_SFX_THROW },
    { "impact",    AG_DUB_SFX_IMPACT },
    { "riser",     AG_DUB_SFX_RISER },
    { "stab",      AG_DUB_SFX_STAB },
    { "sub_drop",  AG_DUB_SFX_SUB_DROP },
    { "airhorn",   AG_DUB_SFX_AIRHORN },
    { "reveal",    AG_DUB_SFX_REVEAL },
    { "bell_hit",  AG_DUB_SFX_BELL_HIT },
    { "jump",      AG_DUB_SFX_JUMP },
    { "win",       AG_DUB_SFX_WIN },
    { "wrong",     AG_DUB_SFX_WRONG },
    { "tick",      AG_DUB_SFX_TICK },
};

static void put_u32(FILE *f, uint32_t v) { fwrite(&v, 4, 1, f); }
static void put_u16(FILE *f, uint16_t v) { fwrite(&v, 2, 1, f); }

/* 16-bit PCM WAV writer (mono or stereo, interleaved) */
static int write_wav(const char *path, const float *inter, int frames, int ch, int sr) {
    FILE *f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); return -1; }
    uint32_t data_bytes = (uint32_t)(frames * ch * 2);
    fwrite("RIFF", 1, 4, f);
    put_u32(f, 36 + data_bytes);
    fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f);
    put_u32(f, 16);
    put_u16(f, 1);                 /* PCM */
    put_u16(f, (uint16_t)ch);
    put_u32(f, (uint32_t)sr);
    put_u32(f, (uint32_t)(sr * ch * 2));
    put_u16(f, (uint16_t)(ch * 2));
    put_u16(f, 16);
    fwrite("data", 1, 4, f);
    put_u32(f, data_bytes);
    for (int i = 0; i < frames * ch; i++) {
        float s = inter[i];
        if (s > 1.0f) s = 1.0f;
        if (s < -1.0f) s = -1.0f;
        int16_t v = (int16_t)lrintf(s * 32767.0f);
        fwrite(&v, 2, 1, f);
    }
    fclose(f);
    return 0;
}

static void analyse(const float *x, int n, float *peak, float *rms) {
    float p = 0.0f, sum = 0.0f;
    for (int i = 0; i < n; i++) {
        float a = fabsf(x[i]);
        if (a > p) p = a;
        sum += x[i] * x[i];
    }
    *peak = p;
    *rms = n ? sqrtf(sum / (float)n) : 0.0f;
}

int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char path[1024];
    char manifest[65536];
    int mlen = 0;

    const int total = (int)(SR * (60.0 / BPM) * 4.0 * BARS);   /* frames */
    float *buf = (float *)calloc((size_t)total * 2, sizeof(float));
    if (!buf) { fprintf(stderr, "oom\n"); return 1; }

    mlen += snprintf(manifest + mlen, sizeof(manifest) - mlen,
        "{\n  \"sampleRate\": %d,\n  \"bpm\": %.1f,\n  \"bars\": %d,\n  \"engine\": \"native/audio_gen/src/ag_dubstep.c\",\n  \"items\": [\n", SR, BPM, BARS);

    int first = 1;
    for (size_t v = 0; v < sizeof(VARIANTS) / sizeof(VARIANTS[0]); v++) {
        AgDubstep d;
        ag_dubstep_init(&d, SR, VARIANTS[v].variant, BPM, 0x11009E7ULL + v * 7919ULL);
        ag_dubstep_set_intensity(&d, 0.92f, 0.05f);
        ag_dubstep_event(&d, AG_DUB_EV_DROP);       /* start at full intensity */
        ag_dubstep_render(&d, buf, total);
        float peak, rms;
        analyse(buf, total * 2, &peak, &rms);
        snprintf(path, sizeof(path), "%s/loop_%s.wav", outdir, VARIANTS[v].name);
        if (write_wav(path, buf, total, 2, SR) != 0) return 1;
        printf("loop_%-9s frames=%d peak=%.3f rms=%.4f\n", VARIANTS[v].name, total, peak, rms);
        mlen += snprintf(manifest + mlen, sizeof(manifest) - mlen,
            "%s    {\"file\":\"loop_%s.wav\",\"type\":\"loop\",\"id\":\"%s\",\"label\":\"%s\",\"variant\":%d,"
            "\"channels\":2,\"frames\":%d,\"seconds\":%.4f,\"peak\":%.5f,\"rms\":%.5f,\"bpm\":%.1f,\"seed\":\"0x%llx\"}",
            first ? "" : ",\n", VARIANTS[v].name, VARIANTS[v].name, VARIANTS[v].label, VARIANTS[v].variant,
            total, (double)total / SR, peak, rms, BPM, (unsigned long long)(0x11009E7ULL + v * 7919ULL));
        first = 0;
    }

    for (size_t s = 0; s < sizeof(SFX) / sizeof(SFX[0]); s++) {
        int frames = ag_dub_sfx_frames(SFX[s].kind, SR);
        if (frames <= 0) continue;
        float *mono = (float *)calloc((size_t)frames, sizeof(float));
        int got = ag_dub_sfx_render(SFX[s].kind, 0.85f, 0x5EED1234ULL + s * 104729ULL, mono, frames, SR);
        float peak, rms;
        analyse(mono, got, &peak, &rms);
        snprintf(path, sizeof(path), "%s/sfx_%s.wav", outdir, SFX[s].name);
        if (write_wav(path, mono, got, 1, SR) != 0) return 1;
        printf("sfx_%-10s frames=%d peak=%.3f rms=%.4f\n", SFX[s].name, got, peak, rms);
        mlen += snprintf(manifest + mlen, sizeof(manifest) - mlen,
            ",\n    {\"file\":\"sfx_%s.wav\",\"type\":\"sfx\",\"id\":\"%s\",\"label\":\"%s\",\"kind\":%d,"
            "\"channels\":1,\"frames\":%d,\"seconds\":%.4f,\"peak\":%.5f,\"rms\":%.5f,\"bpm\":0,\"seed\":\"0x%llx\"}",
            SFX[s].name, SFX[s].name, ag_dub_sfx_name(SFX[s].kind), SFX[s].kind,
            got, (double)got / SR, peak, rms, (unsigned long long)(0x5EED1234ULL + s * 104729ULL));
        free(mono);
    }

    mlen += snprintf(manifest + mlen, sizeof(manifest) - mlen, "\n  ]\n}\n");
    snprintf(path, sizeof(path), "%s/manifest.json", outdir);
    FILE *mf = fopen(path, "wb");
    if (!mf) { fprintf(stderr, "cannot write manifest\n"); return 1; }
    fwrite(manifest, 1, (size_t)mlen, mf);
    fclose(mf);
    free(buf);
    printf("wrote %s\n", path);
    return 0;
}
