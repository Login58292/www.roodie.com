# Roodie Worker Access

This repository is completely separate from Soodie.

Roodie is intended for company-issued worker accounts. Workers use the email/username you assign to them together with a Roodie-only access code.

The Roodie access code is for this system only. It should not be a Gmail, Google, or other third-party account password.

## Worker flow

1. Worker enters the company-issued worker email.
2. Worker enters the Roodie access code you assigned.
3. The request is sent to the separate Roodie Supabase project.
4. Supabase stores the email, request status, timestamp, and a one-way bcrypt hash of the Roodie code.

## Connect the new Roodie Supabase project

1. Create a separate Supabase project for Roodie.
2. Run `supabase-setup.sql` in that project's SQL Editor.
3. Put only that project's public URL and anon/publishable key in `config.js`.
4. Never place a Supabase service-role key in this public repository.

No Soodie repository files or Soodie Supabase data are used or modified.
