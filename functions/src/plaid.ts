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
import {FieldValue, getFirestore} from "firebase-admin/firestore";
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
export const createLinkToken = onCall({secrets}, async (request) => {
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
export const exchangePublicToken = onCall({secrets}, async (request) => {
  const uid = requireUid(request);
  const publicToken = request.data?.publicToken;
  if (typeof publicToken !== "string") {
    throw new HttpsError("invalid-argument", "publicToken is required.");
  }
  const {data} = await plaidClient().itemPublicTokenExchange({
    public_token: publicToken,
  });
  await getFirestore().doc(`plaidItems/${uid}`).set({
    accessToken: data.access_token,
    itemId: data.item_id,
    cursor: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {itemId: data.item_id}; // never return the access_token
});

/** Step 3: pull new/changed transactions and store them as expenses. */
export const syncTransactions = onCall({secrets}, async (request) => {
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
  while (hasMore) {
    const {data} = await client.transactionsSync({
      access_token: accessToken,
      cursor,
    });
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
  await batch.commit();

  return {saved, skipped, removed: removedIds.length};
});
