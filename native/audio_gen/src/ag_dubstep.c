/* Dubstep generator: live wobble score + event one-shots. See ag_dubstep.h. */

#include "ag_dubstep.h"

#include <string.h>

/* ------------------------------------------------------------ small DSP ---- */

static float dub_saw(double p) { return (float)(2.0 * (p - (double)(int)(p + 0.5))); }

static float dub_sqr(double p, double pw) { return (p - (double)(int)p) < pw ? 1.0f : -1.0f; }

static float dub_sin(double p) { return (float)sin(AG_TAU * p); }

static float dub_tri(double p) {
    double x = p - (double)(int)p;
    return (float)(4.0 * fabs(x - 0.5) - 1.0);
}

static float dub_noise(AgRng *rng) { return (float)(ag_rng_next_f64(rng) * 2.0 - 1.0); }

static float dub_exp_env(float t, float decay) {
    /* t seconds, decay = time constant */
    if (t < 0.0f) return 0.0f;
    return expf(-t / (decay > 0.0001f ? decay : 0.0001f));
}

static void ladder_init(AgDubLadder *l, float sr) {
    l->s1 = l->s2 = l->s3 = l->s4 = 0.0f;
    l->cut = 800.0f;
    l->res = 0.6f;
    l->sr = sr;
}

/* Cheap Moog-ish ladder with tanh saturation. cut in Hz, res 0..1.2. */
static float ladder_process(AgDubLadder *l, float in, float cut, float res) {
    float f, fb, x;
    if (cut < 30.0f) cut = 30.0f;
    if (cut > l->sr * 0.45f) cut = l->sr * 0.45f;
    f = 2.0f * (float)sin(AG_PI * (double)cut / (double)l->sr);
    if (f > 1.0f) f = 1.0f;
    fb = res * 4.0f;
    x = in - fb * (l->s4 - 0.35f * in);
    x = tanhf(x * 1.2f);
    l->s1 += f * (x - l->s1);
    l->s2 += f * (l->s1 - l->s2);
    l->s3 += f * (l->s2 - l->s3);
    l->s4 += f * (l->s3 - l->s4);
    return l->s4;
}

static float dub_clip(float x) {
    if (x > 1.6f) x = 1.6f;
    if (x < -1.6f) x = -1.6f;
    return x - (x * x * x) / 6.75f;
}

/* -------------------------------------------------------------- one-shots -- */

static const char *k_dub_sfx_names[AG_DUB_SFX_COUNT] = {
    "gem_hit", "gem_land", "gem_spawn", "throw", "catch", "wobble_blip",
    "sub_drop", "impact", "riser", "stab", "correct", "wrong", "win", "lose",
    "airhorn", "scratch", "reveal", "tick", "jump", "shoot", "bell_hit",
    "pad_note", "plaque_place"
};

const char *ag_dub_sfx_name(int kind) {
    if (kind < 0 || kind >= AG_DUB_SFX_COUNT) return "unknown";
    return k_dub_sfx_names[kind];
}

static float k_dub_sfx_secs[AG_DUB_SFX_COUNT] = {
    0.30f, 0.26f, 0.55f, 0.42f, 0.22f, 0.36f,
    0.90f, 0.95f, 1.30f, 0.45f, 0.85f, 0.80f, 1.60f, 1.20f,
    0.90f, 0.40f, 0.70f, 0.09f, 0.32f, 0.38f, 0.65f,
    0.50f, 0.48f
};

int ag_dub_sfx_frames(int kind, int sr) {
    float s;
    if (sr <= 0) sr = AG_SR_DEFAULT;
    if (kind < 0 || kind >= AG_DUB_SFX_COUNT) return sr / 4;
    s = k_dub_sfx_secs[kind];
    return (int)(s * (float)sr) + 8;
}

int ag_dub_sfx_render(int kind, float energy, uint64_t seed,
                      float *out, int max_frames, int sr) {
    AgRng rng;
    AgDubLadder lad;
    int n, i;
    double sr_d;
    float e = ag_clamp_f(energy, 0.0f, 1.0f);
    double ph = 0.0, ph2 = 0.0, ph3 = 0.0, lfo = 0.0;
    float hp = 0.0f, lp = 0.0f, lp2 = 0.0f;

    if (!out || max_frames <= 0) return 0;
    if (sr <= 0) sr = AG_SR_DEFAULT;
    sr_d = (double)sr;
    if (kind < 0 || kind >= AG_DUB_SFX_COUNT) kind = AG_DUB_SFX_TICK;
    ag_rng_seed(&rng, seed ? seed : (uint64_t)(0x51ED270B + kind * 2654435761u));
    ladder_init(&lad, (float)sr);

    n = ag_dub_sfx_frames(kind, sr);
    if (n > max_frames) n = max_frames;
    for (i = 0; i < n; i++) out[i] = 0.0f;

    switch (kind) {
    case AG_DUB_SFX_GEM_HIT: {
        /* Glass clink: three inharmonic partials, a noise transient and a
         * short sub thump. energy = collision speed. */
        double f0 = 1150.0 + 900.0 * (double)e;
        double parts[3];
        float amps[3];
        parts[0] = f0; parts[1] = f0 * 2.41; parts[2] = f0 * 3.77;
        amps[0] = 0.55f; amps[1] = 0.32f; amps[2] = 0.18f;
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float s = 0.0f;
            int k;
            for (k = 0; k < 3; k++) {
                float a = amps[k] * dub_exp_env(t, 0.055f / (1.0f + 0.7f * (float)k));
                s += a * dub_sin((double)i * parts[k] / sr_d);
            }
            s += dub_noise(&rng) * dub_exp_env(t, 0.006f) * 0.5f * (0.4f + 0.6f * e);
            s += dub_sin((double)i * (70.0 - 26.0 * (double)t) / sr_d)
                 * dub_exp_env(t, 0.07f) * (0.25f + 0.45f * e);
            out[i] = dub_clip(s * (0.35f + 0.65f * e));
        }
        break;
    }
    case AG_DUB_SFX_GEM_LAND: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float body = dub_sin((double)i * (120.0 - 58.0 * (double)t) / sr_d)
                         * dub_exp_env(t, 0.055f);
            float wood = dub_tri((double)i * 320.0 / sr_d) * dub_exp_env(t, 0.03f) * 0.4f;
            float nz = dub_noise(&rng) * dub_exp_env(t, 0.012f) * 0.3f;
            lp += 0.22f * (nz - lp);
            out[i] = dub_clip((body + wood + lp) * (0.4f + 0.6f * e));
        }
        break;
    }
    case AG_DUB_SFX_GEM_SPAWN: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float rise = 1.0f - dub_exp_env(t, 0.20f);
            ph += (420.0 + 1500.0 * (double)rise) / sr_d;
            ph2 += (630.0 + 2250.0 * (double)rise) / sr_d;
            out[i] = (dub_sin(ph) * 0.5f + dub_sin(ph2) * 0.25f)
                     * rise * dub_exp_env(t, 0.42f) * 0.8f;
        }
        break;
    }
    case AG_DUB_SFX_THROW: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float sweep = t / (k_dub_sfx_secs[kind]);
            float cut = 300.0f + 5200.0f * sweep * (0.5f + 0.5f * e);
            float nz = dub_noise(&rng);
            float bp;
            lp += (cut / (float)sr) * 2.0f * (nz - lp);
            hp += (cut * 0.35f / (float)sr) * 2.0f * (lp - hp);
            bp = lp - hp;
            out[i] = bp * sinf(3.14159f * sweep) * (0.5f + 0.5f * e) * 0.9f;
        }
        break;
    }
    case AG_DUB_SFX_CATCH: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            ph += (900.0 - 500.0 * (double)t / 0.2) / sr_d;
            out[i] = (dub_sin(ph) * 0.6f + dub_noise(&rng) * 0.25f)
                     * dub_exp_env(t, 0.035f);
        }
        break;
    }
    case AG_DUB_SFX_WOBBLE_BLIP: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float m, cut, s;
            lfo += 11.0 / sr_d;
            m = 0.5f + 0.5f * dub_sin(lfo);
            ph += 82.0 / sr_d; ph2 += 82.5 / sr_d;
            s = dub_saw(ph) * 0.6f + dub_sqr(ph2, 0.42) * 0.4f;
            cut = 180.0f + 3200.0f * m * (0.4f + 0.6f * e);
            s = ladder_process(&lad, s, cut, 0.72f);
            out[i] = dub_clip(s * 1.6f) * dub_exp_env(t, 0.16f);
        }
        break;
    }
    case AG_DUB_SFX_SUB_DROP: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            double f = 140.0 * pow(0.16, (double)t / 0.8) + 24.0;
            ph += f / sr_d;
            out[i] = dub_clip(dub_sin(ph) * 1.3f) * dub_exp_env(t, 0.42f);
        }
        break;
    }
    case AG_DUB_SFX_IMPACT: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float nz = dub_noise(&rng);
            float sub, crack;
            lp += 0.08f * (nz - lp);
            ph += (58.0 - 22.0 * (double)t) / sr_d;
            sub = dub_sin(ph) * dub_exp_env(t, 0.26f) * 1.1f;
            crack = (nz - lp) * dub_exp_env(t, 0.02f) * 0.7f;
            out[i] = dub_clip(sub + crack + lp * dub_exp_env(t, 0.18f) * 0.9f);
        }
        break;
    }
    case AG_DUB_SFX_RISER: {
        float dur = k_dub_sfx_secs[kind];
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float u = t / dur;
            float nz = dub_noise(&rng);
            float cut = 400.0f + 6000.0f * u * u;
            float bp;
            ph += (180.0 + 900.0 * (double)(u * u)) / sr_d;
            lp += (cut / (float)sr) * 2.2f * (nz - lp);
            hp += (cut * 0.5f / (float)sr) * 2.2f * (lp - hp);
            bp = (lp - hp) * 1.4f;
            out[i] = (bp * 0.7f + dub_saw(ph) * 0.35f) * (0.15f + 0.85f * u * u);
        }
        break;
    }
    case AG_DUB_SFX_STAB: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float m, cut, s;
            lfo += 17.0 / sr_d;
            m = 0.5f + 0.5f * dub_sin(lfo);
            ph += 55.0 / sr_d; ph2 += 55.4 / sr_d; ph3 += 110.0 / sr_d;
            s = dub_saw(ph) * 0.5f + dub_saw(ph2) * 0.4f + dub_sqr(ph3, 0.3) * 0.25f;
            cut = 140.0f + 2600.0f * m;
            s = ladder_process(&lad, s, cut, 0.85f);
            out[i] = dub_clip(s * 2.0f) * dub_exp_env(t, 0.12f);
        }
        break;
    }
    case AG_DUB_SFX_CORRECT: {
        /* rising major stab over a short wobble tail */
        static const double steps[3] = { 0.0, 4.0, 7.0 };
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            int si = (int)(t / 0.10f);
            double f;
            float s, cut, m;
            if (si > 2) si = 2;
            f = ag_midi_to_freq(72.0 + steps[si]);
            ph += f / sr_d;
            s = (dub_sqr(ph, 0.5) * 0.35f + dub_sin(ph) * 0.4f)
                * dub_exp_env(t - (float)si * 0.10f, 0.11f);
            lfo += 9.0 / sr_d;
            m = 0.5f + 0.5f * dub_sin(lfo);
            ph2 += ag_midi_to_freq(36.0) / sr_d;
            cut = 160.0f + 1700.0f * m;
            s += ladder_process(&lad, dub_saw(ph2) * 0.9f, cut, 0.7f)
                 * dub_exp_env(t, 0.35f) * 0.8f;
            out[i] = dub_clip(s);
        }
        break;
    }
    case AG_DUB_SFX_WRONG: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            double f = ag_midi_to_freq(45.0) * pow(0.5, (double)t / 0.55);
            float s, cut, m;
            lfo += 6.5 / sr_d;
            m = 0.5f + 0.5f * dub_sin(lfo);
            ph += f / sr_d;
            ph2 += f * 1.013 / sr_d;
            s = dub_saw(ph) * 0.6f + dub_saw(ph2) * 0.5f;
            cut = 120.0f + 1400.0f * m;
            s = ladder_process(&lad, s, cut, 0.9f);
            out[i] = dub_clip(s * 1.8f) * (1.0f - t / 0.8f > 0.0f ? (1.0f - t / 0.8f) : 0.0f);
        }
        break;
    }
    case AG_DUB_SFX_WIN: {
        static const double mel[6] = { 0, 7, 12, 7, 12, 19 };
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            int si = (int)(t / 0.18f);
            float s, cut, m;
            double f;
            if (si > 5) si = 5;
            f = ag_midi_to_freq(64.0 + mel[si]);
            ph += f / sr_d;
            s = (dub_sqr(ph, 0.45) * 0.3f + dub_sin(ph) * 0.35f)
                * dub_exp_env(t - (float)si * 0.18f, 0.14f);
            lfo += 7.0 / sr_d;
            m = 0.5f + 0.5f * dub_sin(lfo);
            ph2 += ag_midi_to_freq(33.0) / sr_d;
            cut = 150.0f + 2200.0f * m;
            s += ladder_process(&lad, dub_saw(ph2), cut, 0.75f) * 0.9f;
            s += dub_noise(&rng) * dub_exp_env(t, 0.02f) * 0.3f;
            out[i] = dub_clip(s * 0.9f) * (t > 1.4f ? (1.6f - t) / 0.2f : 1.0f);
        }
        break;
    }
    case AG_DUB_SFX_LOSE: {
        static const double mel[4] = { 12, 8, 5, 0 };
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            int si = (int)(t / 0.22f);
            double f;
            float s;
            if (si > 3) si = 3;
            f = ag_midi_to_freq(52.0 + mel[si]) * (1.0 - 0.02 * (double)si);
            ph += f / sr_d;
            s = (dub_saw(ph) * 0.4f + dub_sin(ph * 0.5) * 0.3f)
                * dub_exp_env(t - (float)si * 0.22f, 0.18f);
            s = ladder_process(&lad, s, 700.0f - 380.0f * t, 0.5f);
            out[i] = dub_clip(s * 1.5f);
        }
        break;
    }
    case AG_DUB_SFX_AIRHORN: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            double base = ag_midi_to_freq(62.0) * (1.0 + 0.012 * sin(AG_TAU * 5.5 * (double)t));
            float s, att = t < 0.03f ? t / 0.03f : 1.0f;
            float rel = t > 0.72f ? (0.9f - t) / 0.18f : 1.0f;
            if (rel < 0.0f) rel = 0.0f;
            ph += base / sr_d;
            ph2 += base * 1.5 / sr_d;
            ph3 += base * 2.0 / sr_d;
            s = dub_sqr(ph, 0.5) * 0.35f + dub_sqr(ph2, 0.5) * 0.25f + dub_saw(ph3) * 0.2f;
            s = ladder_process(&lad, s, 2400.0f, 0.35f);
            out[i] = dub_clip(s * 1.7f) * att * rel;
        }
        break;
    }
    case AG_DUB_SFX_SCRATCH: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float rate = 1.0f - 2.0f * fabsf(t / 0.4f - 0.5f);
            float nz = dub_noise(&rng);
            lp += 0.35f * (nz - lp);
            lp2 += 0.08f * (lp - lp2);
            ph += (double)(260.0f + 900.0f * rate) / sr_d;
            out[i] = ((lp - lp2) * 0.7f + dub_sin(ph) * 0.35f)
                     * (0.25f + 0.75f * rate) * 0.9f;
        }
        break;
    }
    case AG_DUB_SFX_REVEAL: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float u = t / k_dub_sfx_secs[kind];
            float nz = dub_noise(&rng);
            float s;
            ph += ag_midi_to_freq(84.0) / sr_d;
            ph2 += ag_midi_to_freq(91.0) / sr_d;
            s = dub_sin(ph) * 0.35f * dub_exp_env(t, 0.22f)
                + dub_sin(ph2) * 0.22f * dub_exp_env(t - 0.06f, 0.20f);
            lp += (600.0f + 5000.0f * u) / (float)sr * 2.0f * (nz - lp);
            s += lp * (1.0f - u) * 0.35f;
            out[i] = dub_clip(s);
        }
        break;
    }
    case AG_DUB_SFX_JUMP: {
        /* Aurora hops across floating stones: rising chirp + resonant whoosh */
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float u = t / k_dub_sfx_secs[kind];
            double f = 160.0 + 520.0 * (double)(u * (2.0f - u));
            float nz = dub_noise(&rng);
            float s, bp;
            ph += f / sr_d;
            s = dub_sin(ph) * 0.65f + dub_tri(ph * 1.5) * 0.35f;
            lp += (500.0f + 3200.0f * u) / (float)sr * 2.0f * (nz - lp);
            hp += (250.0f + 1600.0f * u) / (float)sr * 2.0f * (lp - hp);
            bp = (lp - hp) * 0.45f;
            out[i] = dub_clip((s + bp) * (0.4f + 0.6f * e) * dub_exp_env(t, 0.12f));
        }
        break;
    }
    case AG_DUB_SFX_SHOOT: {
        /* Cannon fires glowing orb: snap transient + pitch falling sine + bass punch */
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            double f = 450.0 * pow(0.08, (double)t / 0.25) + 55.0;
            float nz = dub_noise(&rng);
            float s, body;
            ph += f / sr_d;
            body = dub_sin(ph) * dub_exp_env(t, 0.15f) * 1.1f;
            lp += 0.25f * (nz - lp);
            s = body + (nz - lp) * dub_exp_env(t, 0.018f) * 0.8f + lp * dub_exp_env(t, 0.09f) * 0.5f;
            out[i] = dub_clip(s * (0.5f + 0.5f * e));
        }
        break;
    }
    case AG_DUB_SFX_BELL_HIT: {
        /* Golden bell struck by orb: bright metallic inharmonic chime */
        double f0 = 920.0 + 200.0 * (double)e;
        double partials[4] = { 1.0, 1.74, 2.82, 4.15 };
        float p_amps[4] = { 0.55f, 0.35f, 0.22f, 0.12f };
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float s = 0.0f;
            int k;
            for (k = 0; k < 4; k++) {
                float a = p_amps[k] * dub_exp_env(t, 0.22f / (1.0f + 0.5f * (float)k));
                s += a * dub_sin((double)i * f0 * partials[k] / sr_d);
            }
            s += dub_noise(&rng) * dub_exp_env(t, 0.008f) * 0.4f;
            out[i] = dub_clip(s * (0.4f + 0.6f * e));
        }
        break;
    }
    case AG_DUB_SFX_PAD_NOTE: {
        /* Echo Choir musical pad notes: energy selects pentatonic degree */
        static const double pad_midis[4] = { 65.0, 69.0, 72.0, 76.0 }; /* F4, A4, C5, E5 */
        int note_idx = (int)(e * 3.99f);
        double f = ag_midi_to_freq(pad_midis[note_idx < 4 ? note_idx : 3]);
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float s, env;
            ph += f / sr_d;
            ph2 += (f * 1.004) / sr_d;
            env = (t < 0.04f ? t / 0.04f : 1.0f) * dub_exp_env(t - 0.04f, 0.25f);
            s = (dub_sin(ph) * 0.6f + dub_tri(ph2) * 0.35f) * env;
            s = ladder_process(&lad, s, 1800.0f, 0.2f);
            out[i] = dub_clip(s * 1.2f);
        }
        break;
    }
    case AG_DUB_SFX_PLAQUE_PLACE: {
        /* Plaque arrives on its pedestal: crystal latch chime + sub bump */
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            float s;
            ph += ag_midi_to_freq(77.0) / sr_d;
            ph2 += ag_midi_to_freq(84.0) / sr_d;
            s = (dub_sin(ph) * 0.45f + dub_sin(ph2) * 0.35f) * dub_exp_env(t, 0.16f);
            s += dub_sin((double)i * 68.0 / sr_d) * dub_exp_env(t, 0.06f) * 0.4f;
            out[i] = dub_clip(s * (0.4f + 0.6f * e));
        }
        break;
    }
    case AG_DUB_SFX_TICK:
    default: {
        for (i = 0; i < n; i++) {
            float t = (float)i / (float)sr;
            ph += 2100.0 / sr_d;
            out[i] = (dub_sin(ph) * 0.5f + dub_noise(&rng) * 0.3f)
                     * dub_exp_env(t, 0.012f);
        }
        break;
    }
    }

    /* tiny fade-out so nothing clicks at the tail */
    {
        int fade = sr / 200;
        if (fade > n) fade = n;
        for (i = 0; i < fade; i++) {
            float g = (float)i / (float)fade;
            out[n - 1 - i] *= g;
        }
    }
    return n;
}

/* ------------------------------------------------------------ live engine -- */

/* LFO division table in cycles per beat: 1/2, 3/4, 1, 3/2, 2, 3, 4, 6 */
static const double k_dub_divs[8] = { 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0 };

static void dub_build_pattern(AgDubstep *d) {
    int i;
    for (i = 0; i < AG_DUB_STEPS; i++) {
        d->bass_note[i] = -1;
        d->bass_gate[i] = 0;
        d->wob_div[i] = 2;
    }

    switch (d->variant) {
    case AG_DUB_VARIANT_SUSPENSE: {
        /* 1 gem rolling / tension: heartbeat-like pulse on 0 and 6, quiet wobble */
        d->bass_note[0] = 0;
        d->bass_gate[0] = 1;
        d->wob_div[0] = 1;
        if (ag_rng_next_f64(&d->rng) < 0.6) {
            d->bass_note[6] = 3;
            d->bass_gate[6] = 1;
            d->wob_div[6] = 0;
        }
        break;
    }
    case AG_DUB_VARIANT_GROOVE: {
        /* Both gems placed: driving syncopated groove, aggressive wobble */
        static const int groove_deg[6] = { 0, 3, 5, 7, 10, 12 };
        for (i = 0; i < AG_DUB_STEPS; i++) {
            double r = ag_rng_next_f64(&d->rng);
            if ((i % 2) == 0 || r < 0.4) {
                int deg = groove_deg[(int)(r * 6.0) % 6];
                d->bass_note[i] = deg;
                d->bass_gate[i] = 1;
                d->wob_div[i] = (int)(ag_rng_next_f64(&d->rng) * 8.0) % 8;
            }
        }
        d->bass_note[0] = 0;
        d->bass_gate[0] = 1;
        d->wob_div[0] = 4;
        break;
    }
    case AG_DUB_VARIANT_VICTORY: {
        /* Major pentatonic fanfare arps: 0, 4, 7, 9, 12, 16 */
        static const int maj_deg[6] = { 0, 4, 7, 9, 12, 16 };
        for (i = 0; i < AG_DUB_STEPS; i++) {
            if ((i % 2) == 0) {
                d->bass_note[i] = maj_deg[(i / 2) % 6];
                d->bass_gate[i] = 1;
                d->wob_div[i] = 3;
            }
        }
        d->bass_note[0] = 0;
        d->bass_gate[0] = 1;
        break;
    }
    case AG_DUB_VARIANT_DEFEAT: {
        /* Dark falling minor notes */
        static const int dark_deg[4] = { 10, 7, 3, 0 };
        for (i = 0; i < 4; i++) {
            int step = i * 4;
            d->bass_note[step] = dark_deg[i];
            d->bass_gate[step] = 1;
            d->wob_div[step] = 1;
        }
        break;
    }
    case AG_DUB_VARIANT_TRIAL:
    case AG_DUB_VARIANT_STAGE:
    case AG_DUB_VARIANT_CHILL:
    default: {
        /* minor pentatonic riff, halftime phrasing: long notes with gaps */
        static const int degrees[5] = { 0, 3, 5, 7, 10 };
        for (i = 0; i < AG_DUB_STEPS; i++) {
            double r = ag_rng_next_f64(&d->rng);
            int hold = (i % 4) == 0;
            if (hold || r < 0.45) {
                int deg = degrees[(int)(ag_rng_next_f64(&d->rng) * 5.0) % 5];
                int oct = (r > 0.88) ? 12 : 0;
                d->bass_note[i] = deg + oct;
                d->bass_gate[i] = 1;
            }
            d->wob_div[i] = (int)(ag_rng_next_f64(&d->rng) * 8.0) % 8;
        }
        d->bass_note[0] = 0;
        d->bass_gate[0] = 1;
        d->wob_div[0] = 2;
        break;
    }
    }
}

void ag_dubstep_init(AgDubstep *d, int sr, int variant, double bpm, uint64_t seed) {
    if (!d) return;
    memset(d, 0, sizeof(*d));
    d->sr = sr > 0 ? sr : AG_SR_DEFAULT;
    d->seed = seed ? seed : 0xD0B57E9ULL;
    ag_rng_seed(&d->rng, d->seed);
    d->root = 33;
    d->master = 0.0f;
    d->master_target = 1.0f;
    d->master_step = 1.0f / (0.5f * (float)d->sr);
    d->intensity = 0.55f;
    d->intensity_cur = 0.25f;
    d->intensity_step = 1.0f / (float)d->sr;
    d->active = 1;
    d->step = -1;
    d->step_timer = 0.0;
    ladder_init(&d->ladder, (float)d->sr);
    d->delay_len = d->sr * 3 / 8;
    if (d->delay_len > AG_DUB_DELAY_MAX) d->delay_len = AG_DUB_DELAY_MAX - 1;
    d->delay_fb = 0.32f;
    ag_dubstep_set_variant(d, variant, bpm);
}

void ag_dubstep_set_variant(AgDubstep *d, int variant, double bpm) {
    if (!d) return;
    if (variant < 0 || variant >= AG_DUB_VARIANT_COUNT) variant = AG_DUB_VARIANT_STAGE;
    d->variant = variant;
    if (bpm <= 20.0) {
        switch (variant) {
        case AG_DUB_VARIANT_TRIAL: bpm = 150.0; break;
        case AG_DUB_VARIANT_CHILL: bpm = 128.0; break;
        case AG_DUB_VARIANT_SUSPENSE: bpm = 135.0; break;
        case AG_DUB_VARIANT_GROOVE: bpm = 142.0; break;
        case AG_DUB_VARIANT_VICTORY: bpm = 145.0; break;
        case AG_DUB_VARIANT_DEFEAT: bpm = 110.0; break;
        default: bpm = 140.0; break;
        }
    }
    d->bpm = ag_clamp_d(bpm, 60.0, 220.0);
    d->step_len = 60.0 / d->bpm / 4.0;
    switch (variant) {
    case AG_DUB_VARIANT_TRIAL:
        d->root = 34; d->growl = 0.85f; d->wob_open = 220.0f; d->delay_fb = 0.28f; break;
    case AG_DUB_VARIANT_CHILL:
        d->root = 31; d->growl = 0.25f; d->wob_open = 140.0f; d->delay_fb = 0.42f; break;
    case AG_DUB_VARIANT_SUSPENSE:
        d->root = 33; d->growl = 0.35f; d->wob_open = 120.0f; d->delay_fb = 0.36f; break;
    case AG_DUB_VARIANT_GROOVE:
        d->root = 36; d->growl = 0.90f; d->wob_open = 240.0f; d->delay_fb = 0.30f; break;
    case AG_DUB_VARIANT_VICTORY:
        d->root = 38; d->growl = 0.60f; d->wob_open = 300.0f; d->delay_fb = 0.35f; break;
    case AG_DUB_VARIANT_DEFEAT:
        d->root = 31; d->growl = 0.20f; d->wob_open = 90.0f;  d->delay_fb = 0.45f; break;
    default:
        d->root = 33; d->growl = 0.55f; d->wob_open = 180.0f; d->delay_fb = 0.32f; break;
    }
    dub_build_pattern(d);
}

void ag_dubstep_set_intensity(AgDubstep *d, float intensity, float fade_sec) {
    if (!d) return;
    d->intensity = ag_clamp_f(intensity, 0.0f, 1.0f);
    if (fade_sec < 0.01f) fade_sec = 0.01f;
    d->intensity_step = 1.0f / (fade_sec * (float)d->sr);
}

void ag_dubstep_set_gain(AgDubstep *d, float gain, float fade_sec) {
    if (!d) return;
    d->master_target = ag_clamp_f(gain, 0.0f, 2.0f);
    if (fade_sec < 0.01f) fade_sec = 0.01f;
    d->master_step = 1.0f / (fade_sec * (float)d->sr);
    if (d->master_target > 0.0f) d->active = 1;
}

void ag_dubstep_switch_mode(AgDubstep *d, int variant, float intensity, float fade_sec) {
    if (!d) return;
    ag_dubstep_set_variant(d, variant, 0.0);
    if (intensity >= 0.0f) {
        ag_dubstep_set_intensity(d, intensity, fade_sec);
    }
}

void ag_dubstep_event(AgDubstep *d, int event) {
    if (!d) return;
    d->events_fired++;
    switch (event) {
    case AG_DUB_EV_RISER:
        d->build_total = AG_DUB_STEPS * 2;
        d->build_steps = d->build_total;
        d->riser_env = 0.0f;
        d->riser_pitch = 0.0f;
        break;
    case AG_DUB_EV_DROP:
        d->build_steps = 0;
        d->drop_steps = AG_DUB_STEPS * 4;
        d->intensity = 1.0f;
        d->intensity_step = 1.0f / (0.08f * (float)d->sr);
        ag_dubstep_trigger_sfx(d, AG_DUB_SFX_IMPACT, 1.0f, 0.0f, 0.9f);
        d->sub_env = 1.0f;
        break;
    case AG_DUB_EV_IMPACT:
        ag_dubstep_trigger_sfx(d, AG_DUB_SFX_IMPACT, 0.8f, 0.0f, 0.7f);
        break;
    case AG_DUB_EV_FILL:
        d->fill_bar = 1;
        break;
    case AG_DUB_EV_STAB:
        d->stab_env = 1.0f;
        d->stab_freq = ag_midi_to_freq(d->root + 24);
        break;
    case AG_DUB_EV_BREAK:
        d->break_steps = AG_DUB_STEPS;
        break;
    default:
        d->events_fired--;
        break;
    }
}

void ag_dubstep_trigger_sfx(AgDubstep *d, int kind, float energy, float pan, float gain) {
    int i, oldest = 0, oldest_pos = -1;
    if (!d) return;
    for (i = 0; i < AG_DUB_ONESHOTS; i++) {
        if (!d->shots[i].active) { oldest = i; oldest_pos = -1; break; }
        if (d->shots[i].pos > oldest_pos) { oldest_pos = d->shots[i].pos; oldest = i; }
    }
    d->shots[oldest].active = 1;
    d->shots[oldest].kind = kind;
    d->shots[oldest].energy = ag_clamp_f(energy, 0.0f, 1.0f);
    d->shots[oldest].seed = ag_rng_next_u64(&d->rng);
    d->shots[oldest].pos = 0;
    d->shots[oldest].len = ag_dub_sfx_render(kind, d->shots[oldest].energy,
                                             d->shots[oldest].seed,
                                             d->shots[oldest].buf,
                                             AG_DUB_SHOT_MAX, d->sr);
    d->shots[oldest].gain = gain <= 0.0f ? 0.8f : gain;
    d->shots[oldest].pan = ag_clamp_f(pan, -1.0f, 1.0f);
}

void ag_dubstep_release(AgDubstep *d, float fade_sec) {
    if (!d) return;
    d->master_target = 0.0f;
    if (fade_sec < 0.01f) fade_sec = 0.01f;
    d->master_step = 1.0f / (fade_sec * (float)d->sr);
}

int ag_dubstep_active(const AgDubstep *d) {
    if (!d) return 0;
    if (d->master_target > 0.0f) return 1;
    return d->master > 0.001f;
}

static void dub_step_advance(AgDubstep *d) {
    float inten = d->intensity_cur;
    int s;
    d->step = (d->step + 1) % AG_DUB_STEPS;
    d->steps_played++;
    if (d->step == 0) {
        d->bar++;
        if (d->fill_bar > 0) d->fill_bar--;
        if ((d->bar % 4) == 0) dub_build_pattern(d);
    }
    s = d->step;
    if (d->build_steps > 0) d->build_steps--;
    if (d->drop_steps > 0) d->drop_steps--;
    if (d->break_steps > 0) d->break_steps--;
    if (d->build_steps == 1 && d->build_total > 0) {
        d->build_total = 0;
        ag_dubstep_event(d, AG_DUB_EV_DROP);
    }

    /* ---- drums: halftime, kick on 1 (+ ghosts), snare on 9 ---- */
    if (d->variant == AG_DUB_VARIANT_SUSPENSE) {
        /* Heartbeat sub kicks, muted snare, ticking */
        if (s == 0 || s == 6) {
            d->kick_env = 0.75f;
            d->kick_pitch = 0.6f;
            d->kick_click = 0.1f;
            d->kick_phase = 0.0;
            d->hits_kick++;
        }
        if ((s % 2) == 1) d->hat_env = 0.25f;
    } else if (inten > 0.12f && d->break_steps <= 0) {
        int kick = (s == 0) || (s == 6 && inten > 0.5f) || (s == 10 && inten > 0.75f);
        int snare = (s == 8) || (d->fill_bar && (s == 14));
        if (d->variant == AG_DUB_VARIANT_VICTORY && (s == 4 || s == 12)) kick = 1;
        if (d->fill_bar && (s % 2) == 0 && s >= 8) snare = 1;
        if (kick) {
            d->kick_env = 1.0f;
            d->kick_pitch = 1.0f;
            d->kick_click = 1.0f;
            d->kick_phase = 0.0;
            d->hits_kick++;
        }
        if (snare) {
            d->snare_env = 1.0f;
            d->snare_tone = 1.0f;
            d->snare_phase = 0.0;
            d->hits_snare++;
        }
        if ((s % 2) == 1 || inten > 0.8f) d->hat_env = (s % 4 == 3) ? 0.9f : 0.5f;
        if (s == 8 && inten > 0.6f) d->clap_env = 0.8f;
    } else if (inten > 0.05f) {
        if ((s % 4) == 2) d->hat_env = 0.35f;
    }

    /* ---- bass note ---- */
    if (d->bass_gate[s] && d->bass_note[s] >= 0) {
        int midi = d->root + d->bass_note[s];
        d->sub_target = ag_midi_to_freq(midi - 12);
        if (d->sub_freq <= 0.0) d->sub_freq = d->sub_target;
        d->wob_freq = ag_midi_to_freq(midi);
        d->sub_env = 1.0f;
        d->wob_env = 1.0f;
        d->lfo_rate = k_dub_divs[d->wob_div[s] & 7] * (d->bpm / 60.0);
        if (d->drop_steps > 0) d->lfo_rate *= 1.0 + 0.5 * (double)(d->wob_div[s] & 1);
    }
    if (d->build_steps > 0 && (s % 4) == 0) d->stab_env = 0.6f;
}

void ag_dubstep_render(AgDubstep *d, float *out, int frames) {
    int i, k;
    float inv_sr;
    if (!d || !out || frames <= 0) return;
    inv_sr = 1.0f / (float)d->sr;

    for (i = 0; i < frames; i++) {
        float l = 0.0f, r = 0.0f, mono = 0.0f;
        float inten, drums, wob_lvl;

        /* transport */
        if (d->step_timer <= 0.0) {
            dub_step_advance(d);
            d->step_timer += d->step_len;
        }
        d->step_timer -= (double)inv_sr;

        /* level ramps */
        if (d->intensity_cur < d->intensity) {
            d->intensity_cur += d->intensity_step;
            if (d->intensity_cur > d->intensity) d->intensity_cur = d->intensity;
        } else if (d->intensity_cur > d->intensity) {
            d->intensity_cur -= d->intensity_step;
            if (d->intensity_cur < d->intensity) d->intensity_cur = d->intensity;
        }
        if (d->master < d->master_target) {
            d->master += d->master_step;
            if (d->master > d->master_target) d->master = d->master_target;
        } else if (d->master > d->master_target) {
            d->master -= d->master_step;
            if (d->master < d->master_target) d->master = d->master_target;
        }
        inten = d->intensity_cur;
        if (d->drop_steps > 0) inten = inten < 0.9f ? 0.9f : inten;
        drums = d->break_steps > 0 ? 0.25f : 1.0f;
        wob_lvl = d->break_steps > 0 ? 0.25f : 1.0f;

        /* ---- sub ---- */
        if (d->sub_freq <= 0.0) d->sub_freq = ag_midi_to_freq(d->root - 12);
        d->sub_freq += (d->sub_target - d->sub_freq) * 0.0016;
        d->sub_phase += d->sub_freq * inv_sr;
        if (d->sub_phase > 1.0) d->sub_phase -= 1.0;
        d->sub_env -= inv_sr * 0.9f;
        if (d->sub_env < 0.0f) d->sub_env = 0.0f;
        mono += dub_sin(d->sub_phase) * d->sub_env * (0.45f + 0.35f * inten) * wob_lvl;

        /* ---- wobble bass ---- */
        if (d->wob_freq <= 0.0) d->wob_freq = ag_midi_to_freq(d->root);
        if (d->lfo_rate <= 0.0) d->lfo_rate = d->bpm / 60.0;
        {
            float mod, cut, s, form;
            d->lfo_phase += d->lfo_rate * inv_sr;
            if (d->lfo_phase > 1.0) d->lfo_phase -= 1.0;
            mod = 0.5f + 0.5f * dub_sin(d->lfo_phase);
            mod = mod * mod * (3.0f - 2.0f * mod);
            d->wob_p1 += d->wob_freq * inv_sr;
            d->wob_p2 += d->wob_freq * 1.007 * inv_sr;
            d->wob_p3 += d->wob_freq * 0.5 * inv_sr;
            d->wob_env -= inv_sr * 0.55f;
            if (d->wob_env < 0.0f) d->wob_env = 0.0f;
            s = dub_saw(d->wob_p1) * 0.5f + dub_saw(d->wob_p2) * 0.42f
                + dub_sqr(d->wob_p3, 0.35 + 0.25 * (double)mod) * 0.3f;
            form = s - d->form_z1;
            d->form_z1 += (350.0f + 1800.0f * mod) * inv_sr * 2.0f * form;
            d->form_z2 += (120.0f + 900.0f * mod) * inv_sr * 2.0f * (d->form_z1 - d->form_z2);
            s = ag_lerp_f(s, (d->form_z1 - d->form_z2) * 2.2f, d->growl * 0.6f);
            cut = d->wob_open + (600.0f + 3400.0f * inten) * mod;
            s = ladder_process(&d->ladder, s, cut, 0.62f + 0.30f * inten);
            s = dub_clip(s * (1.4f + 1.4f * inten));
            mono += s * d->wob_env * (0.30f + 0.32f * inten) * wob_lvl;
        }

        /* ---- drums ---- */
        if (d->kick_env > 0.0f) {
            float f = 42.0f + 130.0f * d->kick_pitch * d->kick_pitch;
            d->kick_phase += (double)f * inv_sr;
            mono += dub_sin(d->kick_phase) * d->kick_env * 1.05f * drums;
            mono += dub_noise(&d->rng) * d->kick_click * 0.25f * drums;
            d->kick_env -= inv_sr * 3.2f;
            d->kick_pitch -= inv_sr * 34.0f;
            d->kick_click -= inv_sr * 260.0f;
            if (d->kick_env < 0.0f) d->kick_env = 0.0f;
            if (d->kick_pitch < 0.0f) d->kick_pitch = 0.0f;
            if (d->kick_click < 0.0f) d->kick_click = 0.0f;
        }
        if (d->snare_env > 0.0f) {
            float nz = dub_noise(&d->rng);
            d->noise_z += 0.35f * (nz - d->noise_z);
            d->snare_phase += 185.0 * inv_sr;
            mono += ((nz - d->noise_z) * 0.75f + dub_sin(d->snare_phase) * 0.35f)
                    * d->snare_env * 0.85f * drums;
            d->snare_env -= inv_sr * 6.5f;
            if (d->snare_env < 0.0f) d->snare_env = 0.0f;
        }
        if (d->hat_env > 0.0f) {
            float nz = dub_noise(&d->rng);
            float hp_val = nz - d->hp_z;
            d->hp_z += 0.55f * (nz - d->hp_z);
            mono += hp_val * d->hat_env * 0.22f * drums;
            d->hat_env -= inv_sr * 42.0f;
            if (d->hat_env < 0.0f) d->hat_env = 0.0f;
        }
        if (d->clap_env > 0.0f) {
            mono += dub_noise(&d->rng) * d->clap_env * 0.3f * drums;
            d->clap_env -= inv_sr * 12.0f;
            if (d->clap_env < 0.0f) d->clap_env = 0.0f;
        }

        /* ---- riser during a build ---- */
        if (d->build_steps > 0 && d->build_total > 0) {
            float u = 1.0f - (float)d->build_steps / (float)d->build_total;
            float nz = dub_noise(&d->rng);
            d->riser_phase += (double)(200.0f + 1400.0f * u * u) * inv_sr;
            d->riser_env += (u - d->riser_env) * 0.0008f;
            mono += (nz * 0.35f + dub_saw(d->riser_phase) * 0.3f) * u * u * 0.55f;
        }

        /* ---- stab ---- */
        if (d->stab_env > 0.0f) {
            d->stab_phase += (d->stab_freq > 0.0 ? d->stab_freq : 220.0) * inv_sr;
            mono += dub_sqr(d->stab_phase, 0.3) * d->stab_env * 0.22f;
            d->stab_env -= inv_sr * 7.0f;
            if (d->stab_env < 0.0f) d->stab_env = 0.0f;
        }

        /* DC block + stereo spread */
        {
            float x = mono;
            float y = x - d->dc_x1 + 0.995f * d->dc_y1;
            d->dc_x1 = x;
            d->dc_y1 = y;
            mono = y;
        }
        l = mono;
        r = mono;

        /* ---- one-shots, panned ---- */
        for (k = 0; k < AG_DUB_ONESHOTS; k++) {
            AgDubOneShot *sh = &d->shots[k];
            float v, gl, gr;
            if (!sh->active) continue;
            v = sh->buf[sh->pos] * sh->gain;
            gl = 0.5f * (1.0f - sh->pan);
            gr = 0.5f * (1.0f + sh->pan);
            l += v * (0.5f + gl);
            r += v * (0.5f + gr);
            sh->pos++;
            if (sh->pos >= sh->len) sh->active = 0;
        }

        /* ---- echo ---- */
        {
            float dly = d->delay[d->delay_w];
            float mix = l * 0.25f + dly * d->delay_fb;
            d->delay[d->delay_w] = mix;
            d->delay_w = (d->delay_w + 1) % (d->delay_len > 0 ? d->delay_len : 1);
            l += dly * 0.22f;
            r += dly * 0.16f;
        }

        out[i * 2 + 0] = dub_clip(l * d->master * 0.8f);
        out[i * 2 + 1] = dub_clip(r * d->master * 0.8f);
    }
}
