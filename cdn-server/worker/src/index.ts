import { type Env, requireAuth } from "./auth";
import { handleUploadStart, handleUploadFile } from "./upload";
import { generateManifest } from "./manifest";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // CORS preflight
    if (method === "OPTIONS") {
      return new Response(null, {
        headers: corsHeaders(),
      });
    }

    // Derive the worker's public origin for manifest URLs
    const workerUrl = `${url.protocol}//${url.host}`;

    try {
      // --- Authenticated upload endpoints ---
      if (path.startsWith("/api/upload")) {
        const authError = requireAuth(request, env);
        if (authError) return withCors(authError);

        // POST /api/upload/start
        if (method === "POST" && path === "/api/upload/start") {
          return withCors(await handleUploadStart(request, env));
        }

        // PUT /api/upload/{upload_id}/{filename}
        const putMatch = path.match(/^\/api\/upload\/([a-f0-9-]+)\/(.+)$/);
        if (method === "PUT" && putMatch) {
          const [, uploadId, filename] = putMatch;
          return withCors(await handleUploadFile(request, env, uploadId, filename));
        }

        // POST /api/upload/{upload_id}/complete
        const completeMatch = path.match(
          /^\/api\/upload\/([a-f0-9-]+)\/complete$/
        );
        if (method === "POST" && completeMatch) {
          const [, uploadId] = completeMatch;
          const result = await generateManifest(env, uploadId, workerUrl);
          return withCors(
            new Response(JSON.stringify(result), {
              headers: { "Content-Type": "application/json" },
            })
          );
        }

        return withCors(
          new Response("Not found", { status: 404 })
        );
      }

      // --- Public read endpoints (served from R2) ---

      if (method !== "GET" && method !== "HEAD") {
        return withCors(
          new Response("Method not allowed", { status: 405 })
        );
      }

      // GET /manifests/{slug}.json
      if (path.startsWith("/manifests/") && path.endsWith(".json")) {
        const key = path.slice(1); // strip leading /
        return withCors(await serveR2(env, key, "application/json"));
      }

      // GET /audio/{slug}/{filename}
      if (path.startsWith("/audio/")) {
        const key = path.slice(1);
        const contentType = key.endsWith(".m4a")
          ? "audio/mp4"
          : key.endsWith(".mp3")
            ? "audio/mpeg"
            : key.endsWith(".opus")
              ? "audio/opus"
              : "audio/wav";
        return withCors(await serveR2(env, key, contentType));
      }

      // GET /health
      if (path === "/health") {
        return withCors(new Response("ok"));
      }

      return withCors(new Response("Not found", { status: 404 }));
    } catch (err) {
      const message = err instanceof Error ? err.message : "Internal error";
      return withCors(
        new Response(JSON.stringify({ error: message }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        })
      );
    }
  },
} satisfies ExportedHandler<Env>;

async function serveR2(
  env: Env,
  key: string,
  contentType: string
): Promise<Response> {
  const obj = await env.BUCKET.get(key);
  if (!obj) {
    return new Response("Not found", { status: 404 });
  }
  return new Response(obj.body, {
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=31536000, immutable",
    },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
  };
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(corsHeaders())) {
    headers.set(k, v);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
