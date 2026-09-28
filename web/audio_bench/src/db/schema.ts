import {
  integer,
  pgTable,
  real,
  serial,
  text,
  timestamp,
  varchar,
} from "drizzle-orm/pg-core";

/**
 * A saved bake: one offline render of the real C audio engine
 * (native/audio_gen/src/ag_dubstep.c) plus the measurements taken from the
 * 16-bit WAV that the bake tool wrote.
 */
export const bakes = pgTable("bakes", {
  id: serial("id").primaryKey(),
  variant: varchar("variant", { length: 32 }).notNull(),
  label: varchar("label", { length: 120 }).notNull(),
  sampleRate: integer("sample_rate").notNull(),
  bpm: real("bpm").notNull(),
  seed: varchar("seed", { length: 24 }),
  peak: real("peak"),
  rms: real("rms"),
  crestDb: real("crest_db"),
  durationMs: integer("duration_ms"),
  driftPpm: real("drift_ppm"),
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

/**
 * One measured run of the cost model: per-sample script synthesis (what the
 * web export's GDScript fallback does) against buffer playback on the audio
 * thread (the fix).
 */
export const benchRuns = pgTable("bench_runs", {
  id: serial("id").primaryKey(),
  mode: varchar("mode", { length: 64 }).notNull(),
  sampleRate: integer("sample_rate").notNull(),
  audioSeconds: real("audio_seconds").notNull(),
  costMs: real("cost_ms").notNull(),
  realtimeFactor: real("realtime_factor").notNull(),
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

export type Bake = typeof bakes.$inferSelect;
export type BenchRun = typeof benchRuns.$inferSelect;
