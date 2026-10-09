# Anchor Cloud Functions (Plaid Sandbox)

Three callable functions that keep every Plaid secret off the phone:

| Function | Called when | Writes |
|---|---|---|
| `createLinkToken` | User taps **Connect bank** | nothing (returns a short-lived `link_token`) |
| `exchangePublicToken` | Plaid Link succeeds | `plaidItems/{uid}` (access token, server-only) and `users/{uid}/settings/finance.bank` (status the app can read) |
| `syncTransactions` | After linking, and on **Sync** | `users/{uid}/expenses/{transactionId}`, plus `bank.lastSyncedAt` |

```
App ──createLinkToken──▶ Function ──▶ Plaid   (link_token back to app)
App ──Plaid Link UI──▶ Plaid                  (public_token back to app)
App ──exchangePublicToken──▶ Function ──▶ Plaid   (access_token stays in Firestore, rules deny the app)
App ──syncTransactions──▶ Function ──▶ Plaid ──▶ Firestore ──▶ App's live listener redraws Finance
```

## One-time setup

1. **Blaze plan.** Functions that call an outside API (Plaid) and Secret
   Manager both need the pay-as-you-go plan. Set a budget alert in Google
   Cloud Billing (for example $1) so a mistake can't cost real money.
2. **Plaid keys.** Plaid Dashboard → Developers → Keys → copy `client_id`
   and the **Sandbox** secret.
3. **Register the Android app with Plaid.** Plaid Dashboard → Developers →
   API → *Allowed Android package names* → add `com.example.anchor_app`
   (the `applicationId` in `android/app/build.gradle.kts`).
4. **Store the secrets** (never in code, never in git):
   ```bash
   firebase functions:secrets:set PLAID_CLIENT_ID
   firebase functions:secrets:set PLAID_SECRET
   ```

## Deploy

From the repo root:

```bash
cd functions && npm ci && cd ..
firebase deploy --only functions,firestore:rules
```

`firestore.rules` and the functions ship together because the app
depends on both: the rules allow manual expenses and budgets, and block
the app from writing the server-owned `bank` status field.

If deploy rejects the Node version in `package.json` (`"engines"`), change
it to `"22"` and redeploy.

## Test the backend without the app

```bash
cd functions
npm run build
PLAID_CLIENT_ID=... PLAID_SECRET=... node scripts/smoke.mjs
```

Prints sandbox transactions and the Anchor category each one maps to.

## Sandbox login (inside Plaid Link)

- Institution: **First Platypus Bank** (or any non-OAuth sandbox bank)
- Username `user_good`, password `pass_good`
- If asked for a code: `1234`

Right after linking, Plaid may still be generating the sandbox history and
`syncTransactions` returns `updateStatus: "NOT_READY"`. The app retries a
few times automatically; if it still shows nothing, tap **Sync** again.

## Logs

```bash
firebase functions:log
```
