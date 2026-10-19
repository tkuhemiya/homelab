## Compute

- **Google Cloud**: 1× e2-micro VM (1 GB RAM), 30 GB standard disk, 1 GB/month egress (us-west1, us-central1, us-east1 only)
- **Alwaysdata**: shared hosting account with 1/4 CPU, 256 MB RAM, 1 GB SSD, SSH

## Containers/PaaS

- **Azure Container Apps**: 180,000 vCPU-s, 360,000 GiB-s, 2M requests/month
- **Google Cloud Run**: 180,000 vCPU-s, 360,000 GiB-s, 2M requests/month
- **Leapcell**: Hobby plan, 20 serverless projects up to 3 vCPU / 4 GB each, 1 PostgreSQL
- **IBM Code Engine**: 100,000 vCPU-s, 200,000 GB-s, 100,000 requests/month
- **Northflank**: 2 services, 1 database, 2 cron jobs (always on)
- **Render**: 1 web service at 0.1 CPU / 512 MB, 750 instance-hours/month (sleeps when idle)
- **Back4App**: 1 container, 0.25 CPU, 256 MB RAM, 100 GB/month transfer
- **Azure App Service**: 10 apps on F1 (1 GB, 60 CPU-min/day each)
- **Railway**: $1/month usage credit
- **Hugging Face Spaces**: unlimited static Spaces, 2 ZeroGPU Gradio Spaces

## Serverless/edge

- **Vercel Hobby**: 100 GB data transfer, 1M edge requests, 1M function invocations, 4 active CPU-hours, 360 GB-hours memory, 5,000 image transforms, Blob 1 GB, Edge Config 100k reads, 100 daily cron jobs/project (non-commercial)
- **Cloudflare Workers**: 100,000 requests/day (10 ms CPU); KV 1 GB (100k reads, 1k writes/day); Durable Objects 100k requests/day, 5 GB; Workflows 3,000 steps/day; Hyperdrive 100k queries/day; Logs 200k events/day
- **Cloudflare Pages**: unlimited bandwidth, 500 builds/month, 100 projects
- **Google Cloud Functions**: 2M invocations, 400,000 GB-s, 200,000 GHz-s, 5 GB egress/month
- **Deno Deploy**: 1M requests, 20 GiB egress, 10 CPU-hours, 150 GiB-hours memory, 10 apps, KV 1 GiB/month
- **AWS Lambda**: 1M requests, 400,000 GB-s/month
- **Azure Functions**: 1M requests, 400,000 GB-s/month
- **Val Town**: 100,000 runs/day, 15-minute cron, 1 min per run
- **Zephyr Cloud**: 120 GB bandwidth, 50 GB storage, 1 editor
- **Sevalla**: 100 static sites, 100 GB bandwidth, 600 build minutes/month
- **Azure Static Web Apps**: 100 GB bandwidth/month
- **GitHub Pages**: 1 GB site, 100 GB/month bandwidth
- **Firebase Hosting**: 10 GB storage, 360 MB/day transfer
- **Netlify**: 300 credits/month (≈15 GB bandwidth if used only for bandwidth)

## AI/GPU

- **Kaggle**: NVIDIA P100 GPU, 30+ hours/week, plus TPU quota
- **Modal**: $30/month compute credit, 1 TiB/month egress
- **Google Colab**: free GPU notebooks when available (limits unpublished)
- **Hugging Face ZeroGPU**: 2 ZeroGPU Gradio Spaces
- **Grafana Assistant**: 40M tokens/user/month for 3 users
- **Groq**: gpt-oss-120b / gpt-oss-20b / qwen3.8-27b at 30 req/min, 1,000 req/day, 200K tokens/day each; Whisper 2,000 req/day, 28,800 audio-seconds/day
- **Gemini API**: free tier on most models (per-model limits shown in AI Studio)
- **OpenRouter**: `:free` models at 20 req/min, 50 req/day (1,000/day after any $10 credit purchase)
- **Cloudflare Workers AI**: 10,000 Neurons/day
- **Bolt.new**: 1M tokens/month (300K/day)
- **Exa**: $10/month search credit
- **Parallel**: 5,000 requests/month + $5/month credit
- **Kernel**: $5/month browser credit
- **Browserbase**: 3 concurrent browsers, 1 browser-hour, 1,000 searches, 1,000 fetches/month
- **Firecrawl**: 1,000 credits/month
- **Cloudflare Browser Rendering**: 10 min/day, 3 concurrent browsers
- **Lovable**: 5 credits/day (up to 30/month)
- **Ragie**: 1,000 pages
- **CopilotKit**: 1 developer, 200 threads

## Databases

- **Oracle Autonomous Database**: 2 databases, 1 OCPU + 20 GB each
- **Oracle MySQL HeatWave**: 1 database, 50 GB + 50 GB backup
- **Oracle NoSQL**: 3 tables × 25 GB, 133M reads + 133M writes/month (Phoenix only)
- **Azure SQL Database**: 10 databases, 32 GB + 100,000 vCore-s/month each
- **Azure DocumentDB**: 1 cluster, 32 GB
- **Aiven**: PostgreSQL 1 GB, MySQL 1 GB, Valkey 1 GB RAM, OpenSearch 20 GB / 4 GB RAM, Kafka 250 kb/s
- **Azure Cosmos DB**: 1,000 RU/s + 25 GB
- **AWS DynamoDB**: 25 GB, 25 RCU / 25 WCU
- **Neon**: 100 projects, 100 CU-hours + 1 GB per project (20 GB total), 5 GB egress/month
- **BigQuery**: 10 GiB storage, 1 TiB queries/month
- **Turso**: 100 databases, 5 GB, 500M row reads, 10M row writes/month
- **Cloudflare D1**: 5 GB, 5M row reads/day, 100k row writes/day
- **Prisma Postgres**: 50 databases, 2 GB, 200,000 operations/month
- **Qdrant Cloud**: 1 cluster, 0.5 vCPU / 1 GB RAM / 4 GB disk
- **Nile**: unlimited databases, 1 GB, 50M query tokens/month (no pausing)
- **SpacetimeDB**: 2,500 TeV/month (≈3M function calls, 1 GB storage)
- **Supabase**: 2 projects, 500 MB database, 1 GB file storage, 5 GB egress, 50,000 MAU (pauses after 1 week idle)
- **Firebase Firestore**: 1 GiB, 50k reads/day, 20k writes/day, 10 GiB egress/month
- **Firebase Realtime Database**: 1 GB stored, 10 GB/month download, 100 connections
- **Convex**: 0.5 GB database, 1 GB files, 1M function calls, 20 GB-hours compute/month
- **MongoDB Atlas**: M0 cluster, 512 MB
- **Upstash Redis**: 250 MB, 500k commands, 10 GB bandwidth/month
- **Upstash Vector**: 1 index, 10,000 queries/updates per day
- **SingleStore**: 1 shared workspace
- **IBM Cloudant**: 1 GB
- **Redis Cloud**: 30 MB
- **Render Key Value**: 25 MB
- **Koyeb Postgres**: 0.25 vCPU / 1 GB RAM / 1 GB storage, 5 compute-hours/month

## Storage

- **Oracle Block + Object Storage**: 200 GB block (with 5 backups), 20 GB object storage, 50k API requests/month
- **AWS CloudFront**: 1 TB transfer, 10M requests, 2M functions/month
- **Mux**: 100,000 video delivery minutes/month, 10 videos
- **Firebase Cloud Storage**: 5 GB, 100 GB/month download (Blaze plan, US regions)
- **ImageKit**: 20 GB bandwidth/month, 3 GB storage
- **Cloudflare R2**: 10 GB, 1M Class A, 10M Class B operations/month, no egress fees
- **Backblaze B2**: 10 GB, egress up to 3× stored
- **Vercel Blob**: 1 GB, 10 GB transfer/month
- **Tigris**: 5 GB, 10k Class A, 100k Class B requests/month, no egress fees
- **Google Cloud Storage**: 5 GB (US regions)
- **Neon Object Storage**: 5 GB
- **Supabase Storage**: 1 GB
- **Cloudflare Images**: 5,000 transformations/month

## Observability

- **Axiom**: 500 GB/month ingest, 25 GB storage, 30-day retention
- **New Relic**: 100 GB/month ingest, 1 full user
- **Grafana Cloud**: 10k metric series, 50 GB logs, 50 GB traces, 50 GB profiles, 14-day retention, 3 users, 500 k6 VU-hours, 100k API + 10k browser synthetic checks, 50k frontend sessions/month
- **GCP Cloud Logging**: 50 GiB/month
- **Better Stack**: 10 monitors, 1 status page, 3 GB logs, 3 GB traces, 30 GB metrics, 100k exceptions
- **Honeycomb**: 20M events, 100M metric data points/month
- **Sentry**: 5k errors, 5 GB logs, 5 GB metrics, 5M spans, 50 replays, 1 uptime + 1 cron monitor, 1 user
- **PostHog**: 1M events, 5,000 recordings, 1M feature-flag requests, 100k exceptions, 10 GB logs/month
- **Pydantic Logfire**: 10M records/month
- **Embrace**: 1M sessions/year, 5 users
- **Datadog**: up to 5 hosts, 1-day metric retention
- **UptimeRobot**: 50 monitors at 5-minute intervals
- **Checkly**: 10,000 API checks + 1,000 browser checks/month
- **Healthchecks.io**: 20 cron monitors

## Auth

- **WorkOS AuthKit**: 1M monthly active users
- **Neon Auth**: 60,000 MAU
- **Clerk**: 50,000 monthly retained users per app
- **Firebase Authentication**: 50,000 MAU
- **Supabase Auth**: 50,000 MAU
- **Auth0**: 25,000 MAU
- **Stack Auth**: 10,000 users, 1,000 emails/month
- **Cloudflare Access**: 50 users
- **Unkey**: 1,000 API keys, 150,000 verifications/month
- **Arcjet**: 10,000 requests/month

## Email

- **Brevo**: 300 emails/day
- **Resend**: 3,000 emails/month (100/day), 3 domains
- **Oracle Email Delivery**: 3,000 emails/month
- **Mailgun**: 100 emails/day
- **Cloudflare Email Routing**: unlimited inbound forwarding

## Queues/workflows

- **AWS SQS / SNS / Step Functions**: 1M SQS requests, 1M SNS publishes, 4,000 state transitions/month
- **Inngest**: 50,000 executions, 500,000 events/month
- **Google Pub/Sub**: 10 GiB messages/month
- **Upstash QStash**: 1,000 messages/day, 50 GB bandwidth/month
- **Cloudflare Queues**: 10,000 operations/day
- **Trigger.dev**: $5/month usage credit, 20 concurrent runs, 10 schedules

## CI/dev

- **GitHub Actions**: unlimited minutes on public repos, 2,000 min/month on private repos
- **CircleCI**: 30,000 credits/month (≈6,000 Docker minutes)
- **Blacksmith**: 3,000 minutes/month
- **Google Cloud Build**: 2,500 build-minutes/month
- **Azure DevOps**: 1,800 pipeline minutes/month, 5 users
- **GitLab**: 400 compute minutes/month, 10 GiB per project
- **GitHub Codespaces**: 120 core-hours + 15 GB storage/month
- **Firebase Studio**: 3 workspaces
- **CodeRabbit**: AI review on public repos
- **DeepSource**: open-source repos
- **Graphite**: Hobby plan
- **Greptile**: 50 credits, 1 developer
- **Traycer**: unlimited agent sessions with your own coding agent

## Networking/DNS

- **Cloudflare**: DNS, CDN, unlimited Tunnels, Zero Trust for 50 users
- **Oracle networking**: 10 TB/month egress, 1 flexible load balancer (10 Mbps), 1 network load balancer, site-to-site VPN
- **Tailscale**: 6 users, unlimited devices, 50 tagged resources
- **Azure bandwidth**: 100 GB/month outbound
- **Agora**: 10,000 RTC minutes, 1M signaling messages/month
