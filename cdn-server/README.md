# Tilawa CDN (Cloudflare Worker + R2)

Serverless CDN for Tilawa Quran audio. Users upload their annotated recordings from the app; others add the reciter via a manifest URL.

## Architecture

- **Cloudflare Worker**: Handles upload API and serves files from R2
- **Cloudflare R2**: Stores audio files and manifest JSON (free egress, 10GB free storage)
- **No server to maintain**: Fully serverless, scales automatically

## Setup

### Prerequisites

- [Cloudflare account](https://dash.cloudflare.com/sign-up) (free)
- Node.js 18+
- Wrangler CLI: `npm install -g wrangler`

### Deploy

```bash
# Login to Cloudflare
wrangler login

# Create the R2 bucket
wrangler r2 bucket create tilawa-audio

# Install dependencies
cd cdn-server/worker
npm install

# Set your upload API key (choose any strong secret)
wrangler secret put UPLOAD_API_KEY

# Deploy
wrangler deploy
```

After deploy, Wrangler outputs your Worker URL:
```
https://tilawa-cdn.<your-subdomain>.workers.dev
```

### Configure the App

In `Tilawa/CDN/CDNUploadManager.swift`, update:
- `workerBaseURL` with your Worker URL
- `apiKey` with the same secret you set via `wrangler secret put`

## API

### Upload (authenticated)

All upload endpoints require `Authorization: Bearer <API_KEY>`.

| Endpoint | Method | Body | Response |
|----------|--------|------|----------|
| `/api/upload/start` | POST | `{ reciter_name, short_name?, riwayah, style?, format }` | `{ upload_id, slug }` |
| `/api/upload/{id}/{sss}{aaa}.m4a` | PUT | Audio file binary | `{ ok: true }` |
| `/api/upload/{id}/complete` | POST | — | `{ manifest_url }` |

### Read (public)

| Endpoint | Response |
|----------|----------|
| `/audio/{slug}/{sss}{aaa}.m4a` | Audio file |
| `/manifests/{slug}.json` | Tilawa v1.0 manifest JSON |
| `/health` | `ok` |

## How It Works

1. User completes all 6,236 ayah segments for a reciter+riwayah in the Tilawa app
2. App extracts each segment as a standalone `.m4a` file
3. App uploads files to the Worker, which stores them in R2
4. Worker generates a v1.0 manifest JSON compatible with `ReciterManifestImporter`
5. User gets a shareable manifest URL
6. Others paste the URL in Tilawa's Import from URL flow

## Storage

At reasonable AAC quality, a full Quran is ~1-3 GB per reciter. The R2 free tier (10 GB) covers 3-10 reciters. Beyond that, R2 storage costs $0.015/GB/month with zero egress fees.

## Local Development

```bash
cd cdn-server/worker
npm install
wrangler dev
```

Starts a local Worker with R2 simulation at `http://localhost:8787`.

## Custom Domain (Optional)

To serve from your own domain instead of `workers.dev`:
1. Add a custom domain in the Cloudflare dashboard under Workers & Pages > your worker > Settings > Domains
2. Update `workerBaseURL` in the app
