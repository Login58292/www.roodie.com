# Roodie Worker Access

This repository is completely separate from Soodie.

## Worker flow

1. Worker enters a Gmail/email address.
2. Worker enters a **Roodie-only access code**.
3. The request is sent to a separate Roodie Supabase project.
4. Supabase stores the email, request status, timestamp, and a one-way bcrypt hash of the Roodie code.

The page tells workers not to enter Gmail passwords, Google verification codes, recovery codes, or OTPs.

## Connect the new Roodie Supabase project

1. Create a separate Supabase project for Roodie.
2. Run `supabase-setup.sql` in that project's SQL Editor.
3. Put only that project's public URL and anon/publishable key in `config.js`.
4. Never place a Supabase service-role key in this public repository.

No Soodie repository files or Soodie Supabase data are used or modified.
