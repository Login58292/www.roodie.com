# Roodie Worker Verification

Roodie is now an installable Progressive Web App (PWA).

## Worker flow

1. Worker opens the Roodie website.
2. On supported Android browsers, the worker can tap **Install Roodie app**.
3. The installation receives a random Roodie installation ID stored locally for that installation.
4. Worker taps **Continue with Google**.
5. Google verifies the account.
6. Roodie records:
   - verified Gmail
   - Google's provider account ID
   - Roodie installation ID
7. Supabase creates a **Pending** request for that account + installation.
8. Administrator changes Pending to Approved, Rejected, or Blocked.
9. Worker taps **Check approval**.
10. Only the approved account + installation combination is accepted.

A different browser installation or cleared site storage can result in a new installation ID and therefore a new approval request.

## Installable app files

- `manifest.webmanifest` — PWA metadata
- `sw.js` — service worker
- `icon.svg` — Roodie app icon
- `index.html` — sign-in, install and approval UI

GitHub Pages serves the app over HTTPS, which supports PWA installation in compatible browsers.

## Supabase admin review

Open:

**Table Editor -> roodie_access_review**

The view contains:

- `email`
- `google_account_id`
- `install_id`
- `status`
- timestamps

To approve an installation, edit the source row in:

**Table Editor -> roodie_access_requests**

and change:

`Pending -> Approved`

## Security boundary

Roodie does not collect or read Google/Gmail passwords, OTPs, recovery codes, SMS, browser cookies, saved browser credentials, or authentication secrets.

Google authentication remains on Google's own OAuth page. Roodie receives only the identity information Google makes available through the authorized sign-in flow.

## Future stronger device verification

The PWA installation ID is an application-generated identifier, not a hardware identifier. If Roodie later becomes a native Android app, Android Play Integrity can be added for stronger app/device integrity checks.
