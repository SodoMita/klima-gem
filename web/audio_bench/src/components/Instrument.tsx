"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AudioItem } from "@/lib/manifest";

/** Look-ahead scheduled on the audio clock, never on setTimeout. */
const LEAD = 0.12;
const TARGET_SR = 48000;

type Graph = {
  bus: GainNode;
  filter: BiquadFilterNode;
  shaper: WaveShaperNode;
  master: GainNode;
  limiter: DynamicsCompressorNode;
  analyser: AnalyserNode;
};

type Readouts = {
  sampleRate: number;
  baseLatency: number;
  outputLatency: number;
  lead: number;
  driftPpm: number;
  voices: number;
  queued: number;
};

const EMPTY: Readouts = {
  sampleRate: TARGET_SR,
  baseLatency: 0,
  outputLatency: 0,
  lead: 0,
  driftPpm: 0,
  voices: 0,
  queued: 0,
};

function driveCurve(amount: number): Float32Array<ArrayBuffer> {
  const n = 2048;
  const curve = new Float32Array(n);
  const k = 1 + amount * 70;
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    curve[i] = Math.tanh(k * x) / Math.tanh(k);
  }
  return curve;
}

/**
 * The cost model of the web export's GDScript fallback: every sample computed
 * by script on the main thread, instead of the C engine's output played back on
 * the audio thread.
 */
function perSampleSynthCost(seconds: number, sr: number): number {
  const n = Math.floor(seconds * sr);
  let ph = 0;
  let lfo = 0;
  let z1 = 0;
  let z2 = 0;
  let acc = 0;
  const t0 = performance.now();
  for (let i = 0; i < n; i++) {
    lfo += 140 / 60 / 8 / sr;
    const w = 0.5 - 0.5 * Math.cos(lfo * Math.PI * 2);
    ph += 55 / sr;
    if (ph > 1) ph -= 1;
    const saw = 2 * ph - 1;
    const cut = 0.05 + 0.85 * w;
    z1 += cut * (saw - z1);
    z2 += cut * (z1 - z2);
    acc += z2 * z2;
  }
  const ms = performance.now() - t0;
  if (acc === Number.POSITIVE_INFINITY) return ms;
  return ms;
}

export default function Instrument({
  loops,
  sfx,
  engine,
  bars,
}: {
  loops: AudioItem[];
  sfx: AudioItem[];
  engine: string;
  bars: number;
}) {
  const router = useRouter();
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const needleRef = useRef<HTMLDivElement | null>(null);
  const ctxRef = useRef<AudioContext | null>(null);
  const graphRef = useRef<Graph | null>(null);
  const buffersRef = useRef(new Map<string, AudioBuffer>());
  const sourcesRef = useRef<Array<{ src: AudioBufferSourceNode; gain: GainNode }>>([]);
  const queueRef = useRef<{ item: AudioItem; when: number; gain: number; pan: number }[]>([]);
  const decayRef = useRef<Float32Array>(new Float32Array(64));
  const freqRef = useRef<Uint8Array | null>(null);
  const timeRef = useRef<Uint8Array | null>(null);
  const clockRef = useRef<{ t: number; a: number } | null>(null);
  const statsRef = useRef<Readouts>({ ...EMPTY });
  const lastLeadRef = useRef(0);

  const [current, setCurrent] = useState<string>(loops[0]?.id ?? "");
  const [playing, setPlaying] = useState(false);
  const [ready, setReady] = useState(false);
  const [readouts, setReadouts] = useState<Readouts>(EMPTY);
  const [cutoff, setCutoff] = useState(9000);
  const [res, setRes] = useState(2.2);
  const [drive, setDrive] = useState(0.18);
  const [gainDb, setGainDb] = useState(-6);
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const [bench, setBench] = useState<
    { mode: string; sr: number; costMs: number; audioSeconds: number; factor: number }[]
  >([]);
  const [benchBusy, setBenchBusy] = useState(false);

  const ensureAudio = useCallback((): AudioContext => {
    if (ctxRef.current) return ctxRef.current;
    let ctx: AudioContext;
    try {
      ctx = new AudioContext({ sampleRate: TARGET_SR, latencyHint: "interactive" });
    } catch {
      ctx = new AudioContext();
    }
    const bus = ctx.createGain();
    const filter = ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = cutoff;
    filter.Q.value = res;
    const shaper = ctx.createWaveShaper();
    shaper.curve = driveCurve(drive);
    shaper.oversample = "2x";
    const master = ctx.createGain();
    master.gain.value = Math.pow(10, gainDb / 20);
    const limiter = ctx.createDynamicsCompressor();
    limiter.threshold.value = -3;
    limiter.knee.value = 6;
    limiter.ratio.value = 12;
    limiter.attack.value = 0.003;
    limiter.release.value = 0.18;
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 2048;
    analyser.smoothingTimeConstant = 0.72;
    bus.connect(filter);
    filter.connect(shaper);
    shaper.connect(master);
    master.connect(limiter);
    limiter.connect(analyser);
    analyser.connect(ctx.destination);
    graphRef.current = { bus, filter, shaper, master, limiter, analyser };
    freqRef.current = new Uint8Array(analyser.frequencyBinCount);
    timeRef.current = new Uint8Array(analyser.fftSize);
    ctxRef.current = ctx;
    clockRef.current = { t: performance.now() / 1000, a: ctx.currentTime };
    statsRef.current.sampleRate = ctx.sampleRate;
    return ctx;
  }, [cutoff, res, drive, gainDb]);

  const decode = useCallback(
    async (item: AudioItem): Promise<AudioBuffer> => {
      const hit = buffersRef.current.get(item.id);
      if (hit) return hit;
      const ctx = ensureAudio();
      const res2 = await fetch(`/audio/${item.file}`);
      const ab = await res2.arrayBuffer();
      const buf = await ctx.decodeAudioData(ab);
      buffersRef.current.set(item.id, buf);
      return buf;
    },
    [ensureAudio],
  );

  const stopAll = useCallback((fade = 0.18) => {
    const ctx = ctxRef.current;
    if (!ctx) return;
    for (const s of sourcesRef.current) {
      s.gain.gain.cancelScheduledValues(ctx.currentTime);
      s.gain.gain.setValueAtTime(s.gain.gain.value, ctx.currentTime);
      s.gain.gain.linearRampToValueAtTime(0.0001, ctx.currentTime + fade);
      s.src.stop(ctx.currentTime + fade + 0.02);
    }
    sourcesRef.current = [];
  }, []);

  const play = useCallback(
    async (id: string) => {
      const item = loops.find((l) => l.id === id);
      if (!item) return;
      const ctx = ensureAudio();
      if (ctx.state === "suspended") await ctx.resume();
      setReady(true);
      const buf = await decode(item);
      stopAll(0.22);
      const src = ctx.createBufferSource();
      src.buffer = buf;
      src.loop = true;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, ctx.currentTime);
      g.gain.linearRampToValueAtTime(1, ctx.currentTime + 0.22);
      src.connect(g);
      g.connect(graphRef.current!.bus);
      src.start();
      sourcesRef.current.push({ src, gain: g });
      setCurrent(id);
      setPlaying(true);
    },
    [decode, ensureAudio, loops, stopAll],
  );

  const stop = useCallback(() => {
    stopAll();
    setPlaying(false);
  }, [stopAll]);

  /** Look-ahead scheduler: everything lands on ctx.currentTime, not on timers. */
  const pump = useCallback(() => {
    const ctx = ctxRef.current;
    const g = graphRef.current;
    if (!ctx || !g) return;
    const now = ctx.currentTime;
    while (queueRef.current.length && queueRef.current[0].when < now + LEAD) {
      const job = queueRef.current.shift()!;
      const buf = buffersRef.current.get(job.item.id);
      if (!buf) continue;
      const src = ctx.createBufferSource();
      src.buffer = buf;
      const gn = ctx.createGain();
      gn.gain.value = job.gain;
      const pan = ctx.createStereoPanner();
      pan.pan.value = job.pan;
      src.connect(gn);
      gn.connect(pan);
      pan.connect(g.bus);
      src.start(Math.max(job.when, now + 0.001));
      sourcesRef.current.push({ src, gain: gn });
      lastLeadRef.current = (job.when - now) * 1000;
    }
    // retire finished voices without allocating
    if (sourcesRef.current.length > 32) {
      sourcesRef.current = sourcesRef.current.slice(-24);
    }
  }, []);

  const trigger = useCallback(
    async (item: AudioItem, pan = 0, gain = 0.9) => {
      const ctx = ensureAudio();
      if (ctx.state === "suspended") await ctx.resume();
      setReady(true);
      await decode(item);
      const head = queueRef.current.length;
      queueRef.current.push({
        item,
        when: ctx.currentTime + LEAD * (head === 0 ? 0.5 : 1) + head * 0.02,
        gain,
        pan,
      });
      pump();
    },
    [decode, ensureAudio, pump],
  );

  // visualiser + clock drift meter
  useEffect(() => {
    let raf = 0;
    const reduce =
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const frame = () => {
      raf = requestAnimationFrame(frame);
      const ctx = ctxRef.current;
      const g = graphRef.current;
      pump();

      const canvas = canvasRef.current;
      if (canvas) {
        const dpr = Math.min(2, window.devicePixelRatio || 1);
        const w = canvas.clientWidth;
        const h = canvas.clientHeight;
        if (canvas.width !== Math.floor(w * dpr) || canvas.height !== Math.floor(h * dpr)) {
          canvas.width = Math.floor(w * dpr);
          canvas.height = Math.floor(h * dpr);
        }
        const c2 = canvas.getContext("2d");
        if (c2) {
          c2.setTransform(dpr, 0, 0, dpr, 0, 0);
          c2.clearRect(0, 0, w, h);

          // face grid
          c2.strokeStyle = "rgba(185,196,194,0.10)";
          c2.lineWidth = 1;
          for (let i = 1; i < 8; i++) {
            const x = (w / 8) * i;
            c2.beginPath();
            c2.moveTo(x, 0);
            c2.lineTo(x, h);
            c2.stroke();
          }

          const bins = 64;
          const decay = decayRef.current;
          if (g && freqRef.current && timeRef.current) {
            g.analyser.getByteFrequencyData(freqRef.current as Uint8Array<ArrayBuffer>);
            g.analyser.getByteTimeDomainData(timeRef.current as Uint8Array<ArrayBuffer>);
            const step = Math.floor(freqRef.current.length / bins);
            let sum = 0;
            for (let b = 0; b < bins; b++) {
              let v = 0;
              for (let k = 0; k < step; k++) {
                const s = freqRef.current[b * step + k];
                if (s > v) v = s;
              }
              const norm = Math.min(1, (v / 255) * 1.25);
              decay[b] = Math.max(norm, decay[b] * 0.93);
            }
            for (let i = 0; i < timeRef.current.length; i++) {
              const d = (timeRef.current[i] - 128) / 128;
              sum += d * d;
            }
            const rms = Math.sqrt(sum / timeRef.current.length);
            if (needleRef.current) {
              const angle = -46 + 92 * Math.min(1, rms * 2.6);
              needleRef.current.style.transform = `rotate(${angle.toFixed(2)}deg)`;
            }
          }

          const bw = w / bins;
          for (let b = 0; b < bins; b++) {
            const bh = decay[b] * (h - 18);
            const x = b * bw;
            const grad = b / bins;
            c2.fillStyle =
              grad > 0.78
                ? "rgba(222,91,33,0.85)"
                : `rgba(121,199,154,${0.22 + 0.55 * decay[b]})`;
            c2.fillRect(x + 1, h - bh, Math.max(1, bw - 2), bh);
          }

          // oscilloscope
          if (g && timeRef.current) {
            c2.beginPath();
            c2.strokeStyle = "rgba(222,91,33,0.9)";
            c2.lineWidth = 1.5;
            const n = timeRef.current.length;
            for (let i = 0; i < n; i += 4) {
              const x = (i / n) * w;
              const y = h * 0.34 + ((timeRef.current[i] - 128) / 128) * h * 0.3;
              if (i === 0) c2.moveTo(x, y);
              else c2.lineTo(x, y);
            }
            c2.stroke();
          }
        }
      }

      if (ctx) {
        const nowT = performance.now() / 1000;
        const clock = clockRef.current;
        if (!clock) {
          clockRef.current = { t: nowT, a: ctx.currentTime };
        } else {
          const dt = nowT - clock.t;
          const da = ctx.currentTime - clock.a;
          if (dt > 1.5) {
            statsRef.current.driftPpm = ((da - dt) / dt) * 1e6;
            clockRef.current = { t: nowT, a: ctx.currentTime };
          }
        }
        statsRef.current.baseLatency = (ctx.baseLatency ?? 0) * 1000;
        statsRef.current.outputLatency = (ctx.outputLatency ?? 0) * 1000;
        statsRef.current.lead = lastLeadRef.current;
        statsRef.current.voices = sourcesRef.current.length;
        statsRef.current.queued = queueRef.current.length;
        statsRef.current.sampleRate = ctx.sampleRate;
      }
      if (reduce) cancelAnimationFrame(raf);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  }, [pump]);

  // readouts tick at 5 Hz so React never re-renders per frame
  useEffect(() => {
    const id = window.setInterval(() => setReadouts({ ...statsRef.current }), 200);
    return () => window.clearInterval(id);
  }, []);

  // live macro controls
  useEffect(() => {
    const g = graphRef.current;
    const ctx = ctxRef.current;
    if (!g || !ctx) return;
    g.filter.frequency.setTargetAtTime(cutoff, ctx.currentTime, 0.02);
    g.filter.Q.setTargetAtTime(res, ctx.currentTime, 0.02);
    g.master.gain.setTargetAtTime(Math.pow(10, gainDb / 20), ctx.currentTime, 0.02);
    g.shaper.curve = driveCurve(drive);
  }, [cutoff, res, drive, gainDb]);

  const runBench = useCallback(async () => {
    setBenchBusy(true);
    const rows: { mode: string; sr: number; costMs: number; audioSeconds: number; factor: number }[] =
      [];
    for (const sr of [22050, 48000]) {
      const seconds = 2;
      const costMs = perSampleSynthCost(seconds, sr);
      rows.push({
        mode: `per-sample script synth @${sr}`,
        sr,
        costMs,
        audioSeconds: seconds,
        factor: (seconds * 1000) / costMs,
      });
      await fetch("/api/bench", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          mode: `per-sample script synth @${sr}`,
          sampleRate: sr,
          audioSeconds: seconds,
          costMs,
          note: "main-thread per-sample synthesis (web export fallback model)",
        }),
      }).catch(() => undefined);
    }

    // buffer playback: the fixed path — schedule N pre-baked sources
    const ctx = ensureAudio();
    const item = loops[0];
    let scheduleMs = 0;
    if (item) {
      const buf = await decode(item);
      const t0 = performance.now();
      const tmp: AudioBufferSourceNode[] = [];
      for (let i = 0; i < 200; i++) {
        const s = ctx.createBufferSource();
        s.buffer = buf;
        s.connect(ctx.createGain());
        s.start(ctx.currentTime + 0.05 + (i % 8) * 0.0005);
        tmp.push(s);
      }
      scheduleMs = performance.now() - t0;
      for (const s of tmp) {
        try {
          s.stop();
        } catch {
          /* already stopped */
        }
      }
    }
    rows.push({
      mode: "baked C engine · schedule 200 voices",
      sr: ctx.sampleRate,
      costMs: scheduleMs,
      audioSeconds: 200,
      factor: (200 * 1000) / Math.max(scheduleMs, 0.001),
    });
    await fetch("/api/bench", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        mode: "baked C engine · schedule 200 voices",
        sampleRate: ctx.sampleRate,
        audioSeconds: 200,
        costMs: scheduleMs,
        note: "AudioBufferSourceNode scheduling of ag_dubstep.c output",
      }),
    }).catch(() => undefined);

    setBench(rows);
    setBenchBusy(false);
    router.refresh();
  }, [decode, ensureAudio, loops, router]);

  const saveBake = useCallback(async () => {
    setSaving(true);
    try {
      const res = await fetch("/api/bakes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          variant: current,
          driftPpm: statsRef.current.driftPpm,
          note: note || null,
        }),
      });
      const data = await res.json();
      setFlash(
        data?.row
          ? `SAVED #${data.row.id} · peak ${data.measured.peak.toFixed(3)} · rms ${data.measured.rms.toFixed(4)} · crest ${data.measured.crestDb.toFixed(1)} dB`
          : "SAVE FAILED",
      );
      setNote("");
      router.refresh();
    } catch {
      setFlash("SAVE FAILED");
    } finally {
      setSaving(false);
      window.setTimeout(() => setFlash(null), 6000);
    }
  }, [current, note, router]);

  const loopItems = loops;
  const sfxItems = sfx;

  return (
    <div className="relative">
      <div className="pointer-events-none absolute inset-0 face-texture" aria-hidden />
      <div className="relative grid gap-8 px-6 py-10 lg:grid-cols-[1.35fr_1fr] lg:px-10">
        {/* ------------------------------------------------ display + transport */}
        <div>
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <div className="label text-signal">Generator · ag_dubstep.c</div>
              <h2 className="mt-2 font-display text-[clamp(28px,4vw,46px)] font-extrabold leading-[0.95] tracking-[-0.02em] text-glass">
                LIVE PATCH
                <span className="text-warm-2"> / </span>
                {current.toUpperCase()}
              </h2>
            </div>
            <div className="readout text-right text-[11px] leading-5 text-warm-2">
              <div>
                ENGINE <span className="text-glass">{engine}</span>
              </div>
              <div>
                LOOP <span className="text-glass">{bars} BARS @ 120 BPM</span>
              </div>
              <div>
                SEED{" "}
                <span className="text-glass">
                  {loopItems.find((l) => l.id === current)?.seed ?? "—"}
                </span>
              </div>
            </div>
          </div>

          <div className="inset mt-6 rounded-[3px] border border-black/70 bg-[#0b0d0e] p-3">
            <canvas ref={canvasRef} className="block h-[220px] w-full sm:h-[260px]" />
            <div className="mt-2 flex items-center justify-between border-t border-white/10 pt-2">
              <div className="label text-warm-2">
                SPECTRUM 20 Hz — 20 kHz · SCOPE ±1 FS
              </div>
              <div className="flex items-center gap-2">
                <span
                  className={`lamp ${playing ? "text-led" : "text-warm"}`}
                  aria-hidden
                />
                <span className="label text-warm-2">
                  {playing ? "RUNNING" : "STOPPED"}
                </span>
              </div>
            </div>
          </div>

          {/* transport */}
          <div className="mt-5 flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => play(current)}
              className="btn-hard rounded-[2px] border border-signal bg-signal px-6 py-3 label text-white hover:bg-[#f06a2d]"
            >
              ▶ Play patch
            </button>
            <button
              type="button"
              onClick={stop}
              className="btn-hard rounded-[2px] border border-white/25 px-5 py-3 label text-glass hover:border-signal hover:text-signal"
            >
              ■ Stop
            </button>
            <button
              type="button"
              onClick={() => trigger(sfxItems[3] ?? sfxItems[0], 0, 1)}
              className="btn-hard rounded-[2px] border border-white/25 px-5 py-3 label text-glass hover:border-signal hover:text-signal"
            >
              ⚡ Impact
            </button>
            <div className="ml-auto flex items-center gap-3">
              <label className="label text-warm-2" htmlFor="note">
                Note
              </label>
              <input
                id="note"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="what you hear…"
                className="readout w-44 rounded-[2px] border border-white/15 bg-black/40 px-2 py-2 text-[11px] text-glass placeholder:text-warm-2/60 focus:border-signal focus:outline-none"
              />
              <button
                type="button"
                onClick={saveBake}
                disabled={saving}
                className="btn-hard rounded-[2px] border border-led/60 px-4 py-3 label text-led hover:bg-led hover:text-graphite disabled:opacity-40"
              >
                {saving ? "Saving…" : "Save bake"}
              </button>
            </div>
          </div>
          {flash ? (
            <div className="readout mt-3 rounded-[2px] border border-led/40 bg-led/10 px-3 py-2 text-[11px] text-led">
              {flash}
            </div>
          ) : null}

          {/* variant bank */}
          <div className="mt-8">
            <div className="label text-warm-2">Variant bank — same engine, seeded</div>
            <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-7">
              {loopItems.map((item) => {
                const active = item.id === current;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => play(item.id)}
                    className={`btn-hard group rounded-[2px] border px-3 py-3 text-left ${
                      active
                        ? "border-signal bg-signal/15"
                        : "border-white/15 hover:border-signal/70"
                    }`}
                  >
                    <div
                      className={`label ${active ? "text-signal" : "text-glass"}`}
                    >
                      {item.id}
                    </div>
                    <div className="readout mt-2 text-[10px] leading-4 text-warm-2">
                      {item.seconds.toFixed(2)}s · pk {item.peak.toFixed(2)}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* ------------------------------------------------------ control column */}
        <div className="flex flex-col gap-6">
          <div>
            <div className="label text-warm-2">Macro</div>
            <div className="mt-4 space-y-5">
              {[
                {
                  id: "cutoff",
                  label: "Cutoff",
                  value: cutoff,
                  min: 180,
                  max: 14000,
                  step: 10,
                  display: `${Math.round(cutoff)} Hz`,
                  set: setCutoff,
                },
                {
                  id: "res",
                  label: "Resonance",
                  value: res,
                  min: 0.2,
                  max: 18,
                  step: 0.1,
                  display: res.toFixed(1),
                  set: setRes,
                },
                {
                  id: "drive",
                  label: "Drive",
                  value: drive,
                  min: 0,
                  max: 1,
                  step: 0.01,
                  display: `${Math.round(drive * 100)}%`,
                  set: setDrive,
                },
                {
                  id: "gain",
                  label: "Master",
                  value: gainDb,
                  min: -40,
                  max: 6,
                  step: 0.5,
                  display: `${gainDb.toFixed(1)} dB`,
                  set: setGainDb,
                },
              ].map((k) => {
                const pct = ((k.value - k.min) / (k.max - k.min)) * 100;
                return (
                  <div key={k.id}>
                    <div className="flex items-baseline justify-between">
                      <label className="label text-glass" htmlFor={k.id}>
                        {k.label}
                      </label>
                      <span className="readout text-[11px] text-signal">{k.display}</span>
                    </div>
                    <input
                      id={k.id}
                      type="range"
                      className="knob-track mt-2"
                      min={k.min}
                      max={k.max}
                      step={k.step}
                      value={k.value}
                      style={{ ["--fill" as string]: `${pct}%` }}
                      onChange={(e) => k.set(Number(e.target.value))}
                    />
                  </div>
                );
              })}
            </div>
          </div>

          {/* VU */}
          <div className="rounded-[2px] border border-white/12 bg-black/25 p-4">
            <div className="flex items-center justify-between">
              <div className="label text-warm-2">Program level</div>
              <div className="flex items-center gap-2">
                <span className={`lamp ${ready ? "text-led" : "text-warm"}`} aria-hidden />
                <span className="label text-warm-2">{ready ? "CLOCK LOCK" : "IDLE"}</span>
              </div>
            </div>
            <div className="relative mt-3 h-24 overflow-hidden rounded-[2px] bg-[#0b0d0e] inset">
              <div
                ref={needleRef}
                className="needle absolute bottom-0 left-1/2 h-20 w-[2px] origin-bottom bg-signal"
                style={{ transform: "rotate(-46deg)" }}
              />
              <div className="absolute bottom-0 left-1/2 h-3 w-3 -translate-x-1/2 rounded-full bg-warm-2" />
              <div className="absolute left-3 top-3 label text-warm-2">-40</div>
              <div className="absolute right-3 top-3 label text-signal">+3</div>
            </div>
          </div>

          {/* readouts */}
          <div className="rounded-[2px] border border-white/12 bg-black/25 p-4">
            <div className="label text-warm-2">Transport clock</div>
            <dl className="readout mt-3 grid grid-cols-2 gap-x-6 gap-y-2 text-[11px]">
              {[
                ["sample rate", `${readouts.sampleRate} Hz`],
                ["schedule lead", `${readouts.lead.toFixed(1)} ms`],
                ["clock drift", `${readouts.driftPpm.toFixed(2)} ppm`],
                ["base latency", `${readouts.baseLatency.toFixed(2)} ms`],
                ["output latency", `${readouts.outputLatency.toFixed(2)} ms`],
                ["voices", `${readouts.voices}`],
                ["queued", `${readouts.queued}`],
                ["look-ahead", `${(LEAD * 1000).toFixed(0)} ms`],
              ].map(([k, v]) => (
                <div key={k} className="flex items-baseline justify-between gap-2">
                  <dt className="label text-warm-2">{k}</dt>
                  <dd className="text-glass">{v}</dd>
                </div>
              ))}
            </dl>
            <p className="mt-3 border-t border-white/10 pt-3 text-[11px] leading-5 text-warm-2">
              Drift compares the audio clock with the wall clock over the session.
              Notes are placed on <span className="text-glass">ctx.currentTime</span>{" "}
              with a 120 ms look-ahead — never on{" "}
              <span className="text-glass">setTimeout</span>.
            </p>
          </div>
        </div>
      </div>

      {/* ---------------------------------------------------------- one-shots */}
      <div className="relative border-t border-white/10 px-6 py-8 lg:px-10">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <div className="label text-signal">One-shots · ag_dub_sfx_render()</div>
            <p className="mt-2 max-w-xl text-[13px] leading-6 text-warm-2">
              Cut from the same palette the game uses on the show floor. Each
              trigger is queued and released on the audio clock inside the
              look-ahead window.
            </p>
          </div>
          <div className="readout text-[11px] text-warm-2">
            {sfxItems.length} CUTS · MONO · 48 kHz
          </div>
        </div>
        <div className="mt-5 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
          {sfxItems.map((item, i) => (
            <button
              key={item.id}
              type="button"
              onClick={() => trigger(item, ((i % 5) - 2) * 0.22, 0.85)}
              className="btn-hard rounded-[2px] border border-white/15 px-3 py-3 text-left hover:border-signal hover:bg-signal/10"
            >
              <div className="label text-glass">{item.id}</div>
              <div className="readout mt-2 text-[10px] text-warm-2">
                {item.label.slice(0, 30)}
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* -------------------------------------------------------------- bench */}
      <div className="relative border-t border-white/10 px-6 py-8 lg:px-10">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <div className="label text-signal">Cost bench — run in this browser</div>
            <p className="mt-2 max-w-xl text-[13px] leading-6 text-warm-2">
              The GitHub Pages build computed every sample in script on the main
              thread at 22 050 Hz. This measures that cost against scheduling the
              baked C engine, on your machine, right now.
            </p>
          </div>
          <button
            type="button"
            onClick={runBench}
            disabled={benchBusy}
            className="btn-hard rounded-[2px] border border-signal px-6 py-3 label text-signal hover:bg-signal hover:text-white disabled:opacity-40"
          >
            {benchBusy ? "Measuring…" : "Run bench"}
          </button>
        </div>

        <div className="mt-5 overflow-x-auto">
          <table className="readout w-full min-w-[560px] border-collapse text-[11px]">
            <thead>
              <tr className="border-b border-white/20 text-left">
                <th className="label py-2 font-medium text-warm-2">Mode</th>
                <th className="label py-2 font-medium text-warm-2">Rate</th>
                <th className="label py-2 font-medium text-warm-2">Audio</th>
                <th className="label py-2 font-medium text-warm-2">Cost</th>
                <th className="label py-2 font-medium text-warm-2">Realtime</th>
              </tr>
            </thead>
            <tbody>
              {bench.length === 0 ? (
                <tr>
                  <td colSpan={5} className="py-6 text-warm-2">
                    No run yet — press RUN BENCH to measure this machine.
                  </td>
                </tr>
              ) : (
                bench.map((r) => (
                  <tr key={r.mode} className="border-b border-white/10">
                    <td className="py-2 text-glass">{r.mode}</td>
                    <td className="py-2 text-warm-2">{r.sr} Hz</td>
                    <td className="py-2 text-warm-2">{r.audioSeconds.toFixed(2)} s</td>
                    <td className="py-2 text-warm-2">{r.costMs.toFixed(2)} ms</td>
                    <td
                      className={`py-2 ${r.factor >= 1 ? "text-led" : "text-signal"}`}
                    >
                      {r.factor.toFixed(1)}×
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
