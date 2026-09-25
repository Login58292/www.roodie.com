# Roodie Worker Access

Roodie now uses an automatic **Gmail -> linked Roodie code** flow.

## Worker flow

1. The administrator links a worker Gmail to a Roodie code in Supabase.
2. The worker opens Roodie and taps **Continue with Google**.
3. Google/Supabase verifies the Gmail address.
4. Roodie automatically finds the Roodie code already linked to that Gmail.
5. The worker does **not** type the code.
6. Supabase creates an access request containing the verified Gmail + linked Roodie code.
7. The administrator changes the request from **Pending** to **Approved**, **Rejected**, or **Blocked**.
8. The worker can tap **Check approval**.

## Link a Gmail to a code

In the Roodie Supabase SQL Editor, run:

```sql
select private.admin_set_roodie_email_code(
  'worker@example.com',
  'ROODIE-001'
);
```

You can also review the mappings in:

**Table Editor -> roodie_email_codes**

The important columns are:

- `worker_email`
- `worker_code`
- `status`

## Where the sign-in appears

After the worker signs in with Google, open:

**Table Editor -> roodie_access_requests**

You will see:

- `worker_email` — verified by Google
- `linked_code` — automatically looked up from `roodie_email_codes`
- `status` — Pending / Approved / Rejected / Blocked
- `requested_at`

The worker never has to type the Roodie code.

## Important

The linked Roodie code is an application/workforce code managed by Roodie. It is not a Google password, Google OTP, recovery code, or Google verification code.

If multiple people use the exact same Google account, Google presents them to Roodie as the same identity, so that Gmail can only resolve to the same linked Roodie code unless the system is later changed to use another worker identifier.
