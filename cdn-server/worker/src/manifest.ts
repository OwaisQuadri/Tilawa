import type { Env } from "./auth";

interface SessionMeta {
  slug: string;
  reciter_name: string;
  short_name?: string;
  riwayah: string;
  style?: string;
  format: string;
  version?: number;
}

/**
 * Generates a Tilawa v1.0 manifest JSON and stores it in R2.
 * Returns the public manifest URL.
 */
export async function generateManifest(
  env: Env,
  uploadId: string,
  workerUrl: string
): Promise<{ manifest_url: string; version: number }> {
  // Read session metadata
  const metaObj = await env.BUCKET.get(`_uploads/${uploadId}/meta.json`);
  if (!metaObj) {
    throw new Error("Upload session not found");
  }
  const meta: SessionMeta = await metaObj.json();

  // Build manifest matching ReciterManifestImporter v1.0 schema
  const manifest: Record<string, unknown> = {
    schema_version: "1.0",
    version: meta.version ?? 1,
    reciter: {
      name: meta.reciter_name,
      ...(meta.short_name && { short_name: meta.short_name }),
      riwayah: meta.riwayah,
      ...(meta.style && { style: meta.style }),
    },
    audio: {
      base_url: `${workerUrl}/audio/${meta.slug}/`,
      format: meta.format,
      naming_pattern: "surah_ayah",
    },
  };

  const manifestKey = `manifests/${meta.slug}.json`;
  await env.BUCKET.put(manifestKey, JSON.stringify(manifest, null, 2), {
    httpMetadata: { contentType: "application/json" },
  });

  // Clean up upload session metadata
  await env.BUCKET.delete(`_uploads/${uploadId}/meta.json`);

  return { manifest_url: `${workerUrl}/${manifestKey}`, version: meta.version ?? 1 };
}
