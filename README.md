# Roodie Worker Access

Roodie now uses a two-stage worker access flow.

1. The worker signs in with Google.
2. Google/Supabase verifies the Google account and gives Roodie the verified email/session.
3. The worker enters the separate Roodie worker PIN supplied by the administrator.
4. The PIN request appears in Supabase as Pending.
5. The administrator reviews the request in Supabase and changes its status to Approved, Rejected, or Blocked.
6. The worker taps Check approval using the same Roodie PIN.
7. If the request is Approved, the Roodie page shows Access approved.

## Where to approve workers

Open the Roodie Supabase project and go to:

Table Editor -> roodie_access_requests

A new request contains:

- worker_email — the Google-authenticated email.
- submitted_pin — the Roodie PIN while the request is still Pending.
- status — defaults to Pending.
- requested_at — when the request was submitted.

To allow the worker, change status from Pending to Approved.

The database trigger then automatically removes the visible PIN and stores only a bcrypt hash. The administrator can see the Roodie PIN while reviewing the Pending request, but the plaintext PIN is not retained after the decision.

## Shared Google account

Multiple workers can use the same Google account if that is how the company operates. Give each worker a different Roodie PIN. The PIN becomes the worker-specific access identifier.

If two workers use the same Google account and the same Roodie PIN, Roodie cannot distinguish them as separate workers.

## Google password

Roodie does not receive or store the Gmail/Google password, Google OTP, recovery code, or 2-step-verification code. Google handles those credentials directly.

## Supabase setup

The live Roodie project is configured for this approval flow. For a fresh project:

1. Run supabase-setup.sql.
2. Enable Google under Supabase Authentication providers.
3. Configure the Google OAuth client and Supabase callback URL.
4. Add the deployed GitHub Pages URL to the allowed redirect URLs.
5. Keep only the public Supabase URL and publishable key in config.js.

Never put a Google client secret or Supabase service-role key in the public repository.