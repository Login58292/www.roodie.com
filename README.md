# Roodie Worker Access

Roodie now uses Google identity directly. There is no manual Gmail-to-code setup.

## Worker flow

1. The worker opens Roodie.
2. The worker taps Continue with Google.
3. Google authenticates the account.
4. Supabase gives Roodie the verified Gmail identity.
5. Roodie automatically reads Google's unique account ID for that Google identity.
6. Supabase creates an access request containing the Gmail + Google account ID.
7. The administrator reviews the request and changes Pending to Approved, Rejected, or Blocked.
8. The worker taps Check approval.

The worker does not type any Roodie code.

## Where to review requests

Open the Roodie Supabase project and go to:

Table Editor -> roodie_access_requests

Important columns:

- worker_email — the verified Gmail address.
- google_account_id — Google's unique provider account identifier.
- status — Pending, Approved, Rejected, or Blocked.
- requested_at — when Roodie created the request.
- last_checked_at — the most recent approval check.

To grant access, change status from Pending to Approved.

## Google identity

The Google account ID is obtained automatically from the Google identity attached to the Supabase-authenticated user. It is not manually associated in the roodie_email_codes table.

The Google account ID is also not a Gmail password, OTP, recovery code, or verification code.

## Supabase setup

For a fresh Roodie project:

1. Run supabase-setup.sql.
2. Enable Google under Supabase Authentication providers.
3. Configure the Google OAuth client and Supabase callback URL.
4. Add the deployed Roodie site to the allowed redirect URLs.
5. Keep only the public Supabase URL and publishable key in config.js.

Never expose the Google client secret or Supabase service-role key in the public GitHub repository.
