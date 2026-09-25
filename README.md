# Roodie Worker Access

Roodie is a worker-access page that uses a **verified Google email address** plus a separate **Roodie-issued worker code**.

## Worker flow

1. Worker opens the Roodie link.
2. Worker taps **Continue with Google**.
3. Google authenticates the worker and Supabase gives Roodie the verified email address.
4. Roodie displays that verified email.
5. Worker enters the Roodie access code issued by the company.
6. Roodie checks the verified Google email + Roodie code against the approved worker roster.

If a personalized invite link is used, the invite token must also belong to that same worker.

Roodie does **not** request or store Gmail passwords, Google verification codes, backup codes, or 2-step-verification codes.

## Important browser limitation

A normal website cannot silently inspect a phone and read whichever Gmail account is signed in. The first Google sign-in requires Google's own account-selection/consent flow. After that, Google/Supabase can keep a normal signed-in session on that browser, making later visits much faster.

## Supabase setup

Use a separate Supabase project dedicated to Roodie.

1. Run `supabase-setup.sql` in the Roodie project's SQL Editor.
2. In Supabase Auth, enable the **Google** provider.
3. Create a Google OAuth Web client and add the Supabase callback URL shown by the Google provider page.
4. Add the deployed Roodie URL to the allowed Site URL / redirect URLs.
5. Put only the Roodie project's public project URL and publishable/anon key in `config.js`.
6. Never put the Google client secret, Supabase service-role key, worker codes, or private credentials in this public GitHub repository.

The SQL creates:

- `roodie_workers` — approved worker roster
- `roodie_worker_visits` — personalized-link records
- `roodie_worker_logins` — worker verification results
- `admin_add_roodie_worker(...)` — admin provisioning helper
- `register_roodie_visit(...)` — authenticated invite-link logging
- `register_roodie_worker(...)` — verifies the Google-session email + Roodie code

## Provision a worker

From the Supabase SQL Editor:

```sql
select public.admin_add_roodie_worker(
  'worker1@gmail.com',
  'ROODIE-CODE-001',
  'A_LONG_RANDOM_UNIQUE_TOKEN_FOR_WORKER_1'
);
```

Then give the worker a personalized link:

```
https://YOUR-ROODIE-SITE/?invite=A_LONG_RANDOM_UNIQUE_TOKEN_FOR_WORKER_1
```

The worker's Google account must use the same email that is present in the Roodie roster.
