export interface Env {
  BUCKET: R2Bucket;
  UPLOAD_API_KEY: string;
}

export function requireAuth(request: Request, env: Env): Response | null {
  const header = request.headers.get("Authorization");
  if (!header || !header.startsWith("Bearer ")) {
    return new Response("Missing Authorization header", { status: 401 });
  }
  const token = header.slice(7);
  if (token !== env.UPLOAD_API_KEY) {
    return new Response("Invalid API key", { status: 403 });
  }
  return null; // Auth OK
}
