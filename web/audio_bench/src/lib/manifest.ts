import { readFileSync } from "node:fs";
import path from "node:path";

export type AudioItem = {
  file: string;
  type: "loop" | "sfx";
  id: string;
  label: string;
  variant?: number;
  kind?: number;
  channels: number;
  frames: number;
  seconds: number;
  peak: number;
  rms: number;
  bpm: number;
  seed: string;
};

export type AudioManifest = {
  sampleRate: number;
  bpm: number;
  bars: number;
  engine: string;
  items: AudioItem[];
};

export function loadManifest(): AudioManifest {
  const file = path.join(process.cwd(), "public", "audio", "manifest.json");
  return JSON.parse(readFileSync(file, "utf8")) as AudioManifest;
}

/** Parse a 16-bit PCM WAV written by the bake tool and measure it. */
export function analyseWav(buffer: Buffer): {
  sampleRate: number;
  channels: number;
  frames: number;
  peak: number;
  rms: number;
  crestDb: number;
  durationMs: number;
} {
  const view = new DataView(
    buffer.buffer,
    buffer.byteOffset,
    buffer.byteLength,
  );
  const tag = (o: number) =>
    String.fromCharCode(buffer[o], buffer[o + 1], buffer[o + 2], buffer[o + 3]);

  let sampleRate = 0;
  let channels = 0;
  let bits = 16;
  let dataOffset = 0;
  let dataLength = 0;

  let pos = 12;
  while (pos + 8 <= buffer.length) {
    const id = tag(pos);
    const size = view.getUint32(pos + 4, true);
    if (id === "fmt ") {
      channels = view.getUint16(pos + 10, true);
      sampleRate = view.getUint32(pos + 12, true);
      bits = view.getUint16(pos + 22, true);
    } else if (id === "data") {
      dataOffset = pos + 8;
      dataLength = Math.min(size, buffer.length - dataOffset);
      break;
    }
    pos += 8 + size + (size % 2);
  }

  const bytesPerSample = bits / 8;
  const frames = Math.floor(dataLength / (bytesPerSample * Math.max(channels, 1)));
  let peak = 0;
  let sum = 0;
  for (let i = 0; i < frames * channels; i++) {
    const v = view.getInt16(dataOffset + i * bytesPerSample, true) / 32768;
    const a = Math.abs(v);
    if (a > peak) peak = a;
    sum += v * v;
  }
  const rms = frames * channels > 0 ? Math.sqrt(sum / (frames * channels)) : 0;
  return {
    sampleRate,
    channels,
    frames,
    peak,
    rms,
    crestDb: rms > 0 ? 20 * Math.log10(peak / rms) : 0,
    durationMs: sampleRate > 0 ? (frames / sampleRate) * 1000 : 0,
  };
}
