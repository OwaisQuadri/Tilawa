import type { Env } from "./auth";

const FILENAME_RE = /^\d{3}\d{3}\.\w+$/;

function slugify(name: string, riwayah: string, id: string): string {
  const base = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  const short = id.slice(0, 6);
  return `${base}-${riwayah}-${short}`;
}

interface StartRequest {
  reciter_name: string;
  short_name?: string;
  riwayah: string;
  style?: string;
  format: string;
  folder_id?: string;
}

const VALID_RIWAYAHS = new Set([
  "hafs", "shuabah", "warsh", "qaloon", "bazzi", "qunbul",
  "doori_abu_amr", "soosi", "hisham", "ibn_dhakwan",
  "khalaf_an_hamza", "khallad", "abul_harith", "doori_al_kisai",
  "ibn_wardan", "ibn_jammaz", "ruways", "rawh", "ishaq", "idris",
]);

const VALID_FORMATS = new Set(["mp3", "m4a", "opus", "wav"]);

export async function handleUploadStart(
  request: Request,
  env: Env
): Promise<Response> {
  const body: StartRequest = await request.json();

  if (!body.reciter_name || !body.riwayah || !body.format) {
    return new Response(
      JSON.stringify({ error: "Missing required fields: reciter_name, riwayah, format" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }
  if (!VALID_RIWAYAHS.has(body.riwayah)) {
    return new Response(
      JSON.stringify({ error: `Invalid riwayah: ${body.riwayah}` }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }
  if (!VALID_FORMATS.has(body.format)) {
    return new Response(
      JSON.stringify({ error: `Invalid format: ${body.format}` }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const uploadId = crypto.randomUUID();
  // Reuse existing folder_id if provided (re-upload), otherwise generate a new slug
  const slug = body.folder_id || slugify(body.reciter_name, body.riwayah, uploadId);

  // Read existing manifest to get current version (for re-uploads)
  let version = 1;
  const existingManifest = await env.BUCKET.get(`manifests/${slug}.json`);
  if (existingManifest) {
    try {
      const existing = await existingManifest.json<{ version?: number }>();
      version = (existing.version ?? 0) + 1;
    } catch {
      // Corrupt manifest, start fresh
    }
  }

  const meta = {
    slug,
    reciter_name: body.reciter_name,
    short_name: body.short_name,
    riwayah: body.riwayah,
    style: body.style,
    format: body.format,
    version,
  };

  await env.BUCKET.put(
    `_uploads/${uploadId}/meta.json`,
    JSON.stringify(meta),
    { httpMetadata: { contentType: "application/json" } }
  );

  return new Response(
    JSON.stringify({ upload_id: uploadId, slug }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
}

export async function handleUploadFile(
  request: Request,
  env: Env,
  uploadId: string,
  filename: string
): Promise<Response> {
  if (!FILENAME_RE.test(filename)) {
    return new Response(
      JSON.stringify({ error: `Invalid filename: ${filename}. Expected pattern: SSSAAA.ext` }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify session exists
  const metaObj = await env.BUCKET.get(`_uploads/${uploadId}/meta.json`);
  if (!metaObj) {
    return new Response(
      JSON.stringify({ error: "Upload session not found" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }
  const meta = await metaObj.json<{ slug: string }>();

  const body = request.body;
  if (!body) {
    return new Response(
      JSON.stringify({ error: "Empty request body" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const key = `audio/${meta.slug}/${filename}`;
  await env.BUCKET.put(key, body, {
    httpMetadata: {
      contentType: filename.endsWith(".m4a")
        ? "audio/mp4"
        : filename.endsWith(".mp3")
          ? "audio/mpeg"
          : filename.endsWith(".opus")
            ? "audio/opus"
            : "audio/wav",
    },
  });

  return new Response(
    JSON.stringify({ ok: true }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
}
