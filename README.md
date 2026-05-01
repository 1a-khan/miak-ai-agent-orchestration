# Miak Tech — AI Agent Orchestration System

A self-hosted multi-agent AI system built in Elixir/OTP.
Employees interact via Telegram. Agents handle emails, files, project proposals,
and IT tasks autonomously. Every decision is logged to PostgreSQL.

---

## What Business Problem Does This Solve?

Small consulting and IT firms spend hours triaging emails, routing client requests,
uploading documents, and briefing technical teams. This system replaces those manual
handoffs with a hierarchy of AI agents that work 24/7 — for a fraction of the cost
of SaaS workflow tools.

- Replaces manual email triage → Jordan classifies and routes emails automatically
- Replaces Dropbox/SharePoint chaos → Aria uploads files to S3 with structured metadata
- Replaces "forward this to the dev team" → CTO briefs IT department automatically
- Replaces €2,000/month tools like UiPath → runs on your own VPS for ~$20/month

---

## System Mindmap

```text
                          MIAK TECH
                              |
          ┌───────────────────┼───────────────────┐
          |                   |                   |
      AGENTS            INFRASTRUCTURE         INTEGRATIONS
          |                   |                   |
    ┌─────┼─────┐        ┌────┼────┐         ┌────┼────┐
    |     |     |        |         |         |         |
   CTO  Jordan  Aria  PostgreSQL  OTP    OpenAI   Windmill
    |             |    (logging) (BEAM)  (GPT-4o) (scripts)
    |             |
  ┌─┴─┐        S3 Upload
  |   |        (AWS)
Alex Sara
(IT Dept)
```

---

## Agent Hierarchy

```text
  You (Telegram)
       |
       v
  ┌─────────┐
  │   CTO   │  ← default recipient of all messages
  └────┬────┘
       |
  ┌────┴──────────────┐
  |                   |
  v                   v
┌──────┐        ┌──────────┐
│  IT  │        │  Jordan  │  Email Manager
│ Dept │        └──────────┘
└──┬───┘
   |
 ┌─┴──────────┐
 |            |
 v            v
Alex         Sara
Programmer  Administrator
```

---

## Message Routing Flow

```text
Telegram message arrives
         |
         v
  Is it a photo?
  ┌── YES ──> Aria (file upload flow)
  |
  NO
  |
  v
  APPROVE <id>?
  ┌── YES ──> CTO.approve_theme()
  |
  NO
  |
  v
  "budget"?
  ┌── YES ──> Budget report rendered
  |
  NO
  |
  v
  Starts with @jordan?
  ┌── YES ──> Jordan
  |
  NO
  |
  v
  Starts with @aria?
  ┌── YES ──> Aria
  |
  NO
  |
  v
  Starts with @alex?
  ┌── YES ──> Alex (Programmer)
  |
  NO
  |
  v
  Starts with @sara?
  ┌── YES ──> Sara (Administrator)
  |
  NO
  |
  v
  Aria session active for this chat?
  ┌── YES ──> Aria (confirmation/correction)
  |
  NO
  |
  v
  CTO (default)
```

---

## Email Processing Flow

```text
"check email" command
         |
         v
  Jordan fetches unread emails
  (via Windmill → Microsoft Graph API)
         |
         v
  Classify each email:
  ┌─ Gulp/Randstad domain? ──> move to Gulp folder
  |
  ├─ Known project sender?  ──> pass to CTO for analysis
  |
  └─ Other                  ──> count only, no action
         |
         v
  CTO analyzes project emails (OpenAI)
         |
         v
  Confident it's a project?
  ┌── YES ──> Propose theme in Telegram
  |           "APPROVE <id>" to activate
  |
  └── NO  ──> Jordan sends reply asking for more info
```

---

## File Upload Flow (Aria)

```text
User sends photo/file to Telegram
         |
         v
  Aria downloads file from Telegram
         |
         v
  OpenAI Vision analyzes image
  (detects category, theme, client)
         |
         v
  Parse caption if provided:
  theme: X / project: Y / task: Z / category: X
         |
         v
  Show summary to user — confirm?
         |
    ┌────┴────┐
   YES       NO/corrections
    |             |
    v             v
  Upload        Update fields
  to S3         show again
    |
    v
  Log to files table (PostgreSQL)
  Return presigned URL
```

---

## Theme Approval Flow

```text
New theme proposed (ID shown in Telegram)
         |
         v
  User replies: APPROVE 1
         |
         v
  CTO sets status = 'active' in DB
         |
         v
  CTO briefs IT Department in parallel:
  ┌─────────────────┐
  |  Alex           |  Sara
  |  (Programmer)   |  (Administrator)
  └─────────────────┘
         |
         v
  CTO summarizes IT responses
  Sends summary to Telegram
```

---

## Agents

| Agent               | Name   | Role                         | Budget |
|---------------------|--------|------------------------------|--------|
| CTO                 | —      | Orchestrator, decision maker | $2     |
| Agent.Programmer    | Alex   | Code, APIs, automation       | $4     |
| Agent.Administrator | Sara   | Linux, Docker, monitoring    | $4     |
| Agent.EmailManager  | Jordan | Email triage, send, reply    | $1     |
| Agent.Aria          | Aria   | File uploads, S3, vision     | $1     |

---

## Stack

```text
Telegram Bot API     ← user interface
      |
TelegramPoller       ← Elixir GenServer, polls every 1s
      |
Agent GenServers     ← one OTP process per agent
      |
   ┌──┴──────────────────┐
   |                     |
OpenAI API           Windmill Cloud
(GPT-4o-mini/4o)     (Python scripts)
                          |
                    ┌─────┴──────┐
                    |            |
              MS Graph API    AWS S3
              (email)         (files)
                    |
               PostgreSQL
               (all logging)
```

---

## Running Locally

```bash
cd miak_tech
cp .env.example .env
# fill in .env with your API keys
source .env && iex -S mix
```

Environment variables required:

```text
OPENAI_API_KEY    sk-...
TELEGRAM_TOKEN    bot token from @BotFather
WINDMILL_TOKEN    token from app.windmill.dev
DB_PASSWORD       postgres password
```

Optional (defaults shown):

```text
DB_HOST=localhost
DB_PORT=5432
DB_NAME=oban_elixir
DB_USER=oban
```

---

## Direct Agent Commands (Telegram)

```text
@jordan check email              — classify and triage inbox
@jordan send email to: x@x.com subject: X body: X
@aria                            — file upload (send a photo)
@alex <question>                 — ask the programmer
@sara <question>                 — ask the administrator
APPROVE <id>                     — activate a proposed theme
budget                           — show spending per agent
```

Any other message goes to the CTO directly.

---

## Production Deployment (Coolify)

1. Push to GitHub
2. Create a new app in Coolify — point to repo, set **Docker Compose** as the build type
3. Set the following environment variables in Coolify:

   ```text
   OPENAI_API_KEY    sk-...
   TELEGRAM_TOKEN    bot token from @BotFather
   WINDMILL_TOKEN    token from app.windmill.dev
   DB_PASSWORD       choose a strong password
   GRAFANA_LOKI_URL  https://logs-prod-xxx.grafana.net
   GRAFANA_LOKI_USER numeric user ID from Grafana Cloud
   GRAFANA_API_KEY   glc_...
   ```

   Optional (defaults shown):

   ```text
   DB_USER=oban
   DB_NAME=oban_elixir
   ```

4. Disable health checks — the app has no HTTP server (it uses Telegram polling)
5. Deploy — Coolify builds the image, starts Postgres, waits for it to be healthy, then starts the app

Tables are created automatically on first boot. The Dockerfile uses a multi-stage Alpine build. Final image is ~50MB.

---

## Running Locally with Docker Compose

```bash
# Create a .env file without "export" prefix — docker-compose syntax
cp .env.example .env.docker
# fill in values, then:
docker compose --env-file .env.docker up --build
```

---

## Windmill Scripts

Scripts live in `windmill_scripts/` and must be deployed manually to your Windmill workspace.

| Script       | Windmill path           | Purpose                                    |
|--------------|-------------------------|--------------------------------------------|
| `s3_tool.py` | `u/ammad/files/s3_tool` | Uploads files to S3, returns presigned URL |

### s3_tool setup

Uses these existing **Variables** from your Windmill workspace:

```text
u/ammad/AWS_ACCESS_KEY_ID      AWS access key ID
u/ammad/AWS_SECRET_ACCESS_KEY  AWS secret access key
u/ammad/AWS_S3_BUCKET          S3 bucket name
```

AWS region is read from the `AWS_DEFAULT_REGION` environment variable in Windmill, defaulting to `eu-west-1`.

S3 key structure: `{client}/{theme}/{category}/{uuid}{ext}`
Presigned URLs expire after 7 days.

---

## Database Tables

```text
agents     — name, role, budget_total, budget_used
messages   — every LLM call logged (agent, tokens, cost)
tasks      — CTO→IT delegations with results
themes     — client project proposals (proposed → active)
files      — S3 upload records linked to themes
```
