import { NextResponse } from "next/server";
import { desc, eq } from "drizzle-orm";
import { db } from "@/db";
import { benchRuns } from "@/db/schema";

export const dynamic = "force-dynamic";

export async function GET() {
  const rows = await db
    .select()
    .from(benchRuns)
    .orderBy(desc(benchRuns.createdAt))
    .limit(12);
  return NextResponse.json({ rows });
}

export async function POST(req: Request) {
  let body: {
    mode?: string;
    sampleRate?: number;
    audioSeconds?: number;
    costMs?: number;
    note?: string;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  const mode = (body.mode ?? "").slice(0, 64);
  const sampleRate = Number(body.sampleRate);
  const audioSeconds = Number(body.audioSeconds);
  const costMs = Number(body.costMs);
  if (!mode || !Number.isFinite(sampleRate) || !Number.isFinite(costMs) || costMs <= 0) {
    return NextResponse.json({ error: "bad payload" }, { status: 400 });
  }

  const realtimeFactor = Number.isFinite(audioSeconds)
    ? (audioSeconds * 1000) / costMs
    : 0;

  const [row] = await db
    .insert(benchRuns)
    .values({
      mode,
      sampleRate,
      audioSeconds: Number.isFinite(audioSeconds) ? audioSeconds : 0,
      costMs,
      realtimeFactor,
      note: body.note?.slice(0, 280) ?? null,
    })
    .returning();

  return NextResponse.json({ row }, { status: 201 });
}

export async function DELETE(req: Request) {
  const url = new URL(req.url);
  const id = Number(url.searchParams.get("id"));
  if (!Number.isFinite(id)) {
    return NextResponse.json({ error: "bad id" }, { status: 400 });
  }
  await db.delete(benchRuns).where(eq(benchRuns.id, id));
  return NextResponse.json({ ok: true });
}
