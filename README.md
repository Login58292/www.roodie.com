# Roodie Worker Access

Roodie is completely separate from Soodie.

## What it can do

You can pre-register every worker in the Roodie Supabase project with:

- the worker email you assigned
- a Roodie-only access code
- a unique random invite token

Each worker then receives a personalized Roodie link such as:

`https://YOUR-ROODIE-SITE/?invite=UNIQUE_RANDOM_TOKEN`

When that personalized link is opened, Roodie automatically records the **worker email assigned to that link** in `roodie_worker_visits`. The worker does not need to type the email first.

Roodie can then ask for the separate Roodie access code and verify it against the stored bcrypt hash.

## Important limitation

A normal website cannot inspect the phone and discover which Gmail account is currently signed in. Therefore the automatic identification comes from the worker's **unique Roodie link**, not from reading Gmail information from the device.

## Supabase setup

Run `supabase-setup.sql` in a separate Roodie Supabase project. It creates:

- `roodie_workers` — your pre-registered worker roster
- `roodie_worker_visits` — automatic link-open records
- `roodie_worker_logins` — Roodie code-check results
- `admin_add_roodie_worker(...)` — admin provisioning helper
- `register_roodie_visit(...)` — automatic personalized-link logging
- `register_roodie_worker(...)` — Roodie access-code verification

Then put only that project's public URL and anon/publishable key in `config.js`.

### Provision a worker

From the Supabase SQL Editor, use the helper shown at the bottom of `supabase-setup.sql`. Use a different long random invite token for every worker.

Do not place worker access codes or Supabase service-role keys in this public GitHub repository.
