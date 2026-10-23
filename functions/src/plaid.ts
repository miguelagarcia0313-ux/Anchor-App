/**
 * Plaid Link + transaction sync (sandbox).
 *
 * Flow:  app -> createLinkToken -> Plaid Link UI -> public_token
 *        app -> exchangePublicToken (access_token stays on the server)
 *        app -> syncTransactions -> users/{uid}/expenses/{transactionId}
 *
 * Security: secrets live in Secret Manager, the access_token is never sent
 * to the phone, and every call requires a signed-in Firebase user.
 */
import {onCall, HttpsError, CallableRequest} from "firebase-functions/https";
import {defineSecret} from "firebase-functions/params";
import {getApps, initializeApp} from "firebase-admin/app";
import {
  DocumentReference,
  FieldValue,
  getFirestore,
} from "firebase-admin/firestore";
import {
  Configuration,
  CountryCode,
  PlaidApi,
  PlaidEnvironments,
  Products,
  Transaction,
} from "plaid";
import {categorize} from "./categorize.js";

if (getApps().length === 0) initializeApp();

const PLAID_CLIENT_ID = defineSecret("PLAID_CLIENT_ID");
const PLAID_SECRET = defineSecret("PLAID_SECRET");
const secrets = [PLAID_CLIENT_ID, PLAID_SECRET];
/** Shared options: secrets + a scaling cap so a bug can't run up costs. */
const callOpts = {secrets, maxInstances: 5};

/** @return {PlaidApi} a sandbox client (secrets are read at call time) */
function plaidClient(): PlaidApi {
  return new PlaidApi(new Configuration({
    basePath: PlaidEnvironments.sandbox,
    baseOptions: {headers: {
      "PLAID-CLIENT-ID": PLAID_CLIENT_ID.value(),
      "PLAID-SECRET": PLAID_SECRET.value(),
    }},
  }));
}

/**
 * @param {CallableRequest} request incoming call
 * @return {string} the caller's Firebase uid
 */
function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

/** Step 1: the app asks for a link_token to open Plaid Link. */
export const createLinkToken = onCall(callOpts, async (request) => {
  const uid = requireUid(request);
  const {data} = await plaidClient().linkTokenCreate({
    user: {client_user_id: uid},
    client_name: "Anchor",
    products: [Products.Transactions],
    country_codes: [CountryCode.Us],
    language: "en",
  });
  return {linkToken: data.link_token};
});

/** Step 2: trade the public_token from Link for an access_token. */
export const exchangePublicToken = onCall(callOpts, async (request) => {
  const uid = requireUid(request);
  const publicToken = request.data?.publicToken;
  if (typeof publicToken !== "string") {
    throw new HttpsError("invalid-argument", "publicToken is required.");
  }
  const {data} = await plaidClient().itemPublicTokenExchange({
    public_token: publicToken,
  });
  const db = getFirestore();
  await db.doc(`plaidItems/${uid}`).set({
    accessToken: data.access_token,
    itemId: data.item_id,
    cursor: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  // Public connection status the app CAN read (no tokens in here).
  // Firestore rules stop the app from writing the `bank` field itself.
  await settingsRef(uid).set({
    bank: {
      connected: true,
      institutionName: cleanInstitutionName(request.data?.institutionName),
      linkedAt: FieldValue.serverTimestamp(),
    },
  }, {merge: true});
  return {itemId: data.item_id}; // never return the access_token
});

/**
 * @param {string} uid the user's Firebase uid
 * @return {DocumentReference} users/{uid}/settings/finance
 */
function settingsRef(uid: string): DocumentReference {
  return getFirestore().doc(`users/${uid}/settings/finance`);
}

/**
 * The institution name comes from the phone, so treat it as untrusted:
 * keep it a short plain string or drop it.
 * @param {unknown} value raw value sent by the app
 * @return {string | null} a safe display name, or null
 */
function cleanInstitutionName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().slice(0, 80);
  return trimmed.length > 0 ? trimmed : null;
}

/** Step 3: pull new/changed transactions and store them as expenses. */
export const syncTransactions = onCall(callOpts, async (request) => {
  const uid = requireUid(request);
  const db = getFirestore();
  const itemRef = db.doc(`plaidItems/${uid}`);
  const item = await itemRef.get();
  if (!item.exists) {
    throw new HttpsError("failed-precondition", "No bank connected yet.");
  }

  const client = plaidClient();
  const accessToken = item.get("accessToken") as string;
  let cursor: string | undefined = item.get("cursor") ?? undefined;
  const changed: Transaction[] = [];
  const removedIds: string[] = [];
  let hasMore = true;
  // Plaid prepares a new Item's history in the background. Until that's
  // done, sync returns nothing and this status is "NOT_READY", so the app
  // knows to wait a few seconds and try again instead of showing "empty".
  let updateStatus = "UNKNOWN";
  while (hasMore) {
    const {data} = await client.transactionsSync({
      access_token: accessToken,
      cursor,
    });
    updateStatus = data.transactions_update_status ?? updateStatus;
    changed.push(...data.added, ...data.modified);
    removedIds.push(...data.removed.map((r) => r.transaction_id));
    cursor = data.next_cursor;
    hasMore = data.has_more;
  }

  const expenses = db.collection(`users/${uid}/expenses`);
  let batch = db.batch();
  let ops = 0;
  let saved = 0;
  let skipped = 0;
  const commitIfFull = async () => {
    if (++ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };

  for (const tx of changed) {
    const ref = expenses.doc(tx.transaction_id);
    const category = categorize(tx);
    if (category === null) {
      batch.delete(ref); // not spending (income, transfer, loan)
      skipped++;
    } else {
      // merge: true keeps the user's userCategory if they already edited it.
      batch.set(ref, {
        amount: tx.amount,
        date: tx.date,
        merchantName: tx.merchant_name ?? tx.name,
        plaidCategory: tx.personal_finance_category?.detailed ?? null,
        autoCategory: category,
        pending: tx.pending,
        source: "plaid",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      saved++;
    }
    await commitIfFull();
  }
  for (const id of removedIds) {
    batch.delete(expenses.doc(id));
    await commitIfFull();
  }
  batch.set(itemRef, {cursor}, {merge: true});
  batch.set(settingsRef(uid), {
    bank: {lastSyncedAt: FieldValue.serverTimestamp()},
  }, {merge: true});
  await batch.commit();

  return {saved, skipped, removed: removedIds.length, updateStatus};
});
