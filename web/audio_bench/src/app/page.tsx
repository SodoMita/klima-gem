import Instrument from "@/components/Instrument";
import { db } from "@/db";
import { benchRuns, bakes, type Bake, type BenchRun } from "@/db/schema";
import { loadManifest } from "@/lib/manifest";
import { desc } from "drizzle-orm";

export const dynamic = "force-dynamic";

export default async function Home() {
  const manifest = loadManifest();
  const loops = manifest.items.filter((i) => i.type === "loop");
  const sfx = manifest.items.filter((i) => i.type === "sfx");

  let savedBakes: Bake[] = [];
  let savedBench: BenchRun[] = [];
  try {
    savedBakes = await db.select().from(bakes).orderBy(desc(bakes.createdAt)).limit(12);
    savedBench = await db.select().from(benchRuns).orderBy(desc(benchRuns.createdAt)).limit(8);
  } catch {
    savedBakes = [];
    savedBench = [];
  }

  const defects = [
    {
      n: "01",
      title: "The C engine never loads on the web",
      body: "The web export ships gdextensionLibs: [], so the AudioGen GDExtension in addons/audio_gen/ is not in the wasm build. play_dubstep() finds no engine and falls back to the GDScript pad/pluck score — a different piece of music, which is exactly what the page was playing.",
      fix: "Bake the real engine offline at build time and stream the result. web/audio_bench/tools/bake_loops.c links ag_dubstep.c + ag_common.c and writes the loops and one-shots the web build plays. No script-side synthesis is left anywhere.",
    },
    {
      n: "02",
      title: "Every sample was computed in script, per frame",
      body: "The fallback pumped samples through GDScript at 22 050 Hz inside _process(). Cost scales with sample rate and lands in the frame budget on the main thread — the page audibly slowed down while it played.",
      fix: "Playback moves to the audio thread: AudioBufferSourceNode plays the baked C output. The main thread only schedules voices. The bench below measures both on your machine.",
    },
    {
      n: "03",
      title: "22 050 Hz",
      body: "Half rate. The wobble LFO, hat transients and the sub lose the top octave, saw partials alias into the midrange, and the drop lands with no weight behind it.",
      fix: "48 000 Hz everywhere, per directive. The bake tool hard-codes #define SR 48000 and the AudioContext is opened with sampleRate: 48000, so nothing is resampled anywhere in the chain.",
    },
    {
      n: "04",
      title: "Notes scheduled against the wall clock",
      body: "Events were placed relative to Date.now() rather than the audio clock, so every hit slid against the buffer. The error compounds — tempo wanders and the groove sags, which is what 'slows down' actually sounds like.",
      fix: "One look-ahead scheduler: 120 ms of events placed on ctx.currentTime from a single rAF tick. The drift readout compares the two clocks continuously, in ppm.",
    },
    {
      n: "05",
      title: "Allocation inside the render loop",
      body: "Per-block array allocation in the mixer caused GC pauses, and a pause in the render loop is an audible dropout.",
      fix: "Decay, frequency and time-domain arrays are allocated once and reused every frame; the voice list is recycled instead of rebuilt.",
    },
  ];

  return (
    <div className="grain relative min-h-screen overflow-x-hidden">
      {/* ---------------------------------------------------------- masthead */}
      <header className="relative isolate overflow-hidden border-b border-ink/15">
        <img
          src="/images/chassis.jpg"
          alt="Warm grey anodised studio component with a dark instrument face and one orange switch"
          className="absolute inset-0 h-full w-full object-cover object-right"
          onError={(e) => {
            (e.currentTarget as HTMLImageElement).style.display = "none";
          }}
        />
        <div className="absolute inset-0 bg-gradient-to-r from-paper via-paper/92 to-paper/25" />
        <div className="relative mx-auto flex max-w-[1400px] flex-col gap-8 px-6 pb-10 pt-8 lg:px-10">
          <div className="flex flex-wrap items-center gap-4">
            <svg width="34" height="34" viewBox="0 0 48 48" aria-hidden className="shrink-0">
              <path
                d="M14 6h20l8 10-18 26L6 16 14 6Z"
                fill="none"
                stroke="#22201D"
                strokeWidth="2.2"
                strokeLinejoin="round"
              />
              <path d="M6 16h36" stroke="#22201D" strokeWidth="2.2" />
              <path d="M17 16l7 26 7-26" fill="none" stroke="#DE5B21" strokeWidth="2.2" strokeLinejoin="round" />
            </svg>
            <div className="label text-ink/70">
              SodoMita / klima-gem · branch gem-dev-16-miku-9v2
            </div>
            <div className="ml-auto flex items-center gap-2">
              <span className="lamp text-led" aria-hidden />
              <span className="label text-ink/70">48 000 Hz · clock locked</span>
            </div>
          </div>

          <h1 className="font-display text-[clamp(44px,9vw,132px)] font-extrabold uppercase leading-[0.82] tracking-[-0.035em] text-ink">
            Klima Gem
            <br />
            <span className="text-signal">Audio</span> Bench
          </h1>

          <div className="grid gap-6 md:grid-cols-[minmax(0,44ch)_1fr]">
            <p className="text-[15px] leading-7 text-ink/85">
              The web export played the wrong music and dragged the page down
              with it. This bench runs the real{" "}
              <span className="readout text-ink">ag_dubstep.c</span> engine
              offline, bakes it at 48 kHz, and plays it back with sample-accurate
              scheduling — the same patches the GDExtension produces natively,
              with no GDScript anywhere in the audio path.
            </p>
            <dl className="readout grid grid-cols-2 gap-x-8 gap-y-3 self-end text-[11px] sm:grid-cols-4">
              {[
                ["engine", "ag_dubstep.c"],
                ["sample rate", "48 000 Hz"],
                ["loops baked", String(loops.length)],
                ["one-shots", String(sfx.length)],
                ["scheduler", "120 ms look-ahead"],
                ["synthesis", "build-time C"],
                ["fallback", "removed"],
                ["bpm", "120"],
              ].map(([k, v]) => (
                <div key={k} className="rule pt-2">
                  <dt className="label text-warm">{k}</dt>
                  <dd className="mt-1 text-[13px] text-ink">{v}</dd>
                </div>
              ))}
            </dl>
          </div>
        </div>
      </header>

      {/* -------------------------------------------------------- instrument */}
      <section id="instrument" className="panel relative isolate border-b border-black/60">
        <Instrument loops={loops} sfx={sfx} engine={manifest.engine} bars={manifest.bars} />
      </section>

      {/* ----------------------------------------------- rail + notes spread */}
      <div className="mx-auto flex max-w-[1400px] gap-10 px-6 py-14 lg:px-10">
        {/* patch sheet rail */}
        <aside className="sticky top-6 hidden h-fit w-[248px] shrink-0 lg:block">
          <div className="label border-b border-ink/25 pb-2 text-ink">Patch sheet</div>
          <ul className="mt-4 space-y-3">
            {loops.map((l) => (
              <li key={l.id} className="rule pt-2">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="label text-ink">{l.id}</span>
                  <span className="readout text-[10px] text-warm">
                    {(l.seconds).toFixed(2)}s
                  </span>
                </div>
                <p className="mt-1 text-[11px] leading-4 text-warm">{l.label}</p>
                <p className="readout mt-1 text-[10px] text-warm-2">
                  pk {l.peak.toFixed(3)} · rms {l.rms.toFixed(4)}
                </p>
              </li>
            ))}
          </ul>

          <div className="label mt-10 border-b border-ink/25 pb-2 text-ink">Signal path</div>
          <ol className="readout mt-4 space-y-2 text-[10px] leading-5 text-warm">
            {[
              "ag_dubstep.c (C99, seeded)",
              "bake_loops.c @ 48 000 Hz",
              "16-bit PCM WAV, 2 bars",
              "AudioBufferSourceNode",
              "lowpass → tanh drive",
              "gain → limiter → analyser",
              "destination",
            ].map((s, i) => (
              <li key={s} className="flex gap-2">
                <span className="text-signal">{String(i + 1).padStart(2, "0")}</span>
                <span>{s}</span>
              </li>
            ))}
          </ol>

          <a
            href="https://github.com/SodoMita/klima-gem"
            className="btn-hard mt-10 inline-flex w-full items-center justify-between border border-ink/25 px-3 py-3 label text-ink hover:border-signal hover:text-signal"
          >
            Repository
            <span aria-hidden>↗</span>
          </a>
        </aside>

        {/* notes */}
        <main className="min-w-0 flex-1">
          <section>
            <div className="flex flex-wrap items-end justify-between gap-4 border-b border-ink/25 pb-3">
              <h2 className="font-display text-[clamp(26px,3.4vw,42px)] font-bold uppercase leading-none tracking-[-0.02em]">
                Why it broke
              </h2>
              <div className="label text-warm">service notes · web export playback</div>
            </div>

            <div className="mt-8 space-y-10">
              {defects.map((d) => (
                <article key={d.n} className="grid gap-5 md:grid-cols-[52px_1fr]">
                  <div className="readout text-[26px] leading-none text-signal">{d.n}</div>
                  <div>
                    <h3 className="font-display text-[19px] font-semibold leading-snug tracking-[-0.01em]">
                      {d.title}
                    </h3>
                    <p className="mt-2 max-w-[68ch] text-[14px] leading-7 text-ink/80">
                      {d.body}
                    </p>
                    <p className="mt-3 max-w-[68ch] border-l-2 border-signal pl-4 text-[13px] leading-6 text-ink">
                      <span className="label text-signal">Fix — </span>
                      {d.fix}
                    </p>
                  </div>
                </article>
              ))}
            </div>
          </section>

          {/* bench + saves */}
          <section className="mt-16">
            <div className="flex flex-wrap items-end justify-between gap-4 border-b border-ink/25 pb-3">
              <h2 className="font-display text-[clamp(26px,3.4vw,42px)] font-bold uppercase leading-none tracking-[-0.02em]">
                Bake log
              </h2>
              <div className="label text-warm">postgres · measured from the wav</div>
            </div>

            <div className="mt-6 overflow-x-auto">
              <table className="readout w-full min-w-[620px] border-collapse text-[11px]">
                <thead>
                  <tr className="border-b border-ink/25 text-left">
                    {["#", "variant", "rate", "bpm", "peak", "rms", "crest", "drift", "note"].map(
                      (h) => (
                        <th key={h} className="label py-2 font-medium text-warm">
                          {h}
                        </th>
                      ),
                    )}
                  </tr>
                </thead>
                <tbody>
                  {savedBakes.length === 0 ? (
                    <tr>
                      <td colSpan={9} className="py-6 text-warm">
                        Nothing saved yet. Play a patch and press SAVE BAKE — the server
                        re-reads the WAV and records peak, RMS, crest factor and clock drift.
                      </td>
                    </tr>
                  ) : (
                    savedBakes.map((b) => (
                      <tr key={b.id} className="border-b border-ink/12">
                        <td className="py-2 text-signal">{b.id}</td>
                        <td className="py-2 text-ink">{b.variant}</td>
                        <td className="py-2 text-warm">{b.sampleRate}</td>
                        <td className="py-2 text-warm">{b.bpm.toFixed(0)}</td>
                        <td className="py-2 text-warm">{b.peak?.toFixed(3)}</td>
                        <td className="py-2 text-warm">{b.rms?.toFixed(4)}</td>
                        <td className="py-2 text-warm">{b.crestDb?.toFixed(1)} dB</td>
                        <td className="py-2 text-warm">
                          {b.driftPpm == null ? "—" : `${b.driftPpm.toFixed(2)} ppm`}
                        </td>
                        <td className="max-w-[22ch] truncate py-2 text-warm">{b.note ?? "—"}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            <div className="label mt-12 border-b border-ink/25 pb-2 text-ink">
              Cost bench — stored runs
            </div>
            <div className="mt-4 overflow-x-auto">
              <table className="readout w-full min-w-[560px] border-collapse text-[11px]">
                <thead>
                  <tr className="border-b border-ink/25 text-left">
                    {["mode", "rate", "audio", "cost", "realtime", "when"].map((h) => (
                      <th key={h} className="label py-2 font-medium text-warm">
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {savedBench.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="py-6 text-warm">
                        Run the bench in the instrument band to store measurements here.
                      </td>
                    </tr>
                  ) : (
                    savedBench.map((r) => (
                      <tr key={r.id} className="border-b border-ink/12">
                        <td className="py-2 text-ink">{r.mode}</td>
                        <td className="py-2 text-warm">{r.sampleRate} Hz</td>
                        <td className="py-2 text-warm">{r.audioSeconds.toFixed(2)} s</td>
                        <td className="py-2 text-warm">{r.costMs.toFixed(2)} ms</td>
                        <td
                          className={`py-2 ${r.realtimeFactor >= 1 ? "text-ink" : "text-signal"}`}
                        >
                          {r.realtimeFactor.toFixed(1)}×
                        </td>
                        <td className="py-2 text-warm-2">
                          {new Date(r.createdAt).toISOString().slice(11, 19)}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </section>

          {/* godot hand-off */}
          <section className="mt-16">
            <div className="flex flex-wrap items-end justify-between gap-4 border-b border-ink/25 pb-3">
              <h2 className="font-display text-[clamp(26px,3.4vw,42px)] font-bold uppercase leading-none tracking-[-0.02em]">
                Hand-off to the game
              </h2>
              <div className="label text-warm">per directive · no gdscript audio</div>
            </div>
            <div className="mt-6 grid gap-6 md:grid-cols-2">
              <div className="border border-ink/20 p-5">
                <div className="label text-signal">Path A — baked loops (ships today)</div>
                <p className="mt-3 text-[13px] leading-6 text-ink/80">
                  Run <span className="readout">bake_loops</span> in CI, commit{" "}
                  <span className="readout">web/audio_bench/public/audio/</span>, and have the
                  web build play the loops through <span className="readout">AudioStreamWAV</span>{" "}
                  / an <span className="readout">AudioStreamPlayer</span>. Delete the GDScript
                  generator path outright. Tempo and intensity switch on variant boundaries,
                  crossfaded over 220 ms.
                </p>
              </div>
              <div className="border border-ink/20 p-5">
                <div className="label text-signal">Path B — the engine compiled to wasm</div>
                <p className="mt-3 text-[13px] leading-6 text-ink/80">
                  Yes — GDExtensions can run on the web: build{" "}
                  <span className="readout">libaudio_gen.wasm32.nothreads.a</span> with{" "}
                  <span className="readout">emcc</span>, list it in{" "}
                  <span className="readout">gdextensionLibs</span>, and export with a template
                  that has <span className="readout">wasm</span> enabled. Heavier CI, but the
                  live engine keeps its dynamic intensity and event API.
                </p>
              </div>
            </div>
          </section>
        </main>
      </div>

      {/* ---------------------------------------------------------- footer */}
      <footer className="border-t border-ink/20 bg-paper-2">
        <div className="mx-auto flex max-w-[1400px] flex-wrap items-center gap-x-8 gap-y-3 px-6 py-8 lg:px-10">
          <div className="label text-ink">Klima Gem audio bench</div>
          <div className="readout text-[11px] text-warm">
            agent gem-dev-16-miku-9v2 · baked {loops.length} loops + {sfx.length} one-shots ·
            engine {manifest.engine}
          </div>
          <a
            href="https://sodomita.github.io/klima-gem/"
            className="readout ml-auto text-[11px] text-signal underline decoration-signal/40 underline-offset-4 hover:decoration-signal"
          >
            sodomita.github.io/klima-gem ↗
          </a>
        </div>
      </footer>
    </div>
  );
}
