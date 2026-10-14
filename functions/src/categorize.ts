/**
 * Maps a Plaid transaction to one of Anchor's Finance categories.
 *
 * Order of checks:
 *   1. Skip anything that isn't spending (money in, transfers, loans).
 *   2. Known subscription merchants -> "subscriptions".
 *   3. Plaid's personal_finance_category -> Anchor category.
 *   4. Everything else -> "miscellaneous".
 *
 * The user can always override the result in the app (userCategory);
 * this only sets the starting value (autoCategory).
 * Taxonomy reference: https://plaid.com/documents/pfc-taxonomy-all.csv
 */

export type AnchorCategory =
  | "groceries"
  | "eating_out"
  | "subscriptions"
  | "entertainment"
  | "miscellaneous";

/** Common subscription merchants, lowercase, punctuation removed. */
export const SUBSCRIPTION_MERCHANTS: string[] = [
  "netflix",
  "hulu",
  "spotify",
  "youtube",
  "golds gym",
  "planet fitness",
];

/** Plaid primary categories that are not spending. */
const SKIPPED_PRIMARY = new Set([
  "INCOME",
  "TRANSFER_IN",
  "TRANSFER_OUT",
  "LOAN_DISBURSEMENTS",
  "LOAN_PAYMENTS",
]);

/** The subset of a Plaid transaction this file needs. */
export interface CategorizableTx {
  amount: number;
  name?: string | null;
  merchant_name?: string | null;
  personal_finance_category?: {primary: string; detailed: string} | null;
}

/**
 * "GOLD'S GYM #0412" -> "golds gym 0412"
 * @param {string} s raw merchant text
 * @return {string} normalized text
 */
export function normalize(s: string): string {
  return s
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * @param {CategorizableTx} tx a Plaid transaction
 * @return {AnchorCategory | null} category, or null if not spending
 */
export function categorize(tx: CategorizableTx): AnchorCategory | null {
  // Plaid: positive amount = money leaving the account.
  if (tx.amount <= 0) return null;

  const pfc = tx.personal_finance_category;
  if (pfc && SKIPPED_PRIMARY.has(pfc.primary)) return null;

  const merchant = ` ${normalize(tx.merchant_name ?? tx.name ?? "")} `;
  if (SUBSCRIPTION_MERCHANTS.some((m) => merchant.includes(` ${m} `))) {
    return "subscriptions";
  }

  if (!pfc) return "miscellaneous";
  if (pfc.detailed === "FOOD_AND_DRINK_GROCERIES") return "groceries";
  if (pfc.primary === "FOOD_AND_DRINK") return "eating_out";
  if (pfc.primary === "ENTERTAINMENT") return "entertainment";
  return "miscellaneous";
}
