import { NextResponse } from "next/server";
import { readFileSync } from "node:fs";
import path from "node:path";
import { desc } from "drizzle-orm";
import { db } from "@/db";
import { bakes } from "@/db/schema";
import { analyseWav, loadManifest } from "@/lib/manifest";

export const dynamic = "force-dynamic";

export async function GET() {
  const rows = await db
    .select()
    .from(bakes)
    .orderBy(desc(bakes.createdAt))
    .limit(24);
  return NextResponse.json({ rows });
}

export async function POST(req: Request) {
  let body: {
    variant?: string;
    sampleRate?: number;
    bpm?: number;
    seed?: string;
    driftPpm?: number;
    note?: string;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  const manifest = loadManifest();
  const item = manifest.items.find(
    (i) => i.id === body.variant && i.type === "loop",
  );
  if (!item) {
    return NextResponse.json({ error: "unknown variant" }, { status: 400 });
  }

  // Server-side audit: measure the WAV that the C bake tool actually wrote.
  const file = path.join(process.cwd(), "public", "audio", item.file);
  const measured = analyseWav(readFileSync(file));

  const [row] = await db
    .insert(bakes)
    .values({
      variant: item.id,
      label: item.label,
      sampleRate: measured.sampleRate,
      bpm: item.bpm,
      seed: item.seed,
      peak: measured.peak,
      rms: measured.rms,
      crestDb: measured.crestDb,
      durationMs: Math.round(measured.durationMs),
      driftPpm: Number.isFinite(body.driftPpm) ? body.driftPpm : null,
      note: body.note?.slice(0, 280) ?? null,
    })
    .returning();

  return NextResponse.json({ row, measured }, { status: 201 });
}
