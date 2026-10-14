import { Configuration, PlaidApi, PlaidEnvironments, Products } from "plaid";
import { categorize } from "../lib/categorize.js"; // run `npm run build` first

const plaid = new PlaidApi(new Configuration({
  basePath: PlaidEnvironments.sandbox,
  baseOptions: { headers: {
    "PLAID-CLIENT-ID": process.env.PLAID_CLIENT_ID,
    "PLAID-SECRET": process.env.PLAID_SECRET,
  }},
}));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

try {
  const { data: pt } = await plaid.sandboxPublicTokenCreate({
    institution_id: "ins_109508",
    initial_products: [Products.Transactions],
  });
  const { data: ex } = await plaid.itemPublicTokenExchange({ public_token: pt.public_token });
  console.log("item_id:", ex.item_id);

  // Plaid prepares transactions in the background; retry until they arrive.
  let added = [];
  for (let attempt = 1; attempt <= 10 && added.length === 0; attempt++) {
    let cursor, hasMore = true;
    while (hasMore) {
      const { data } = await plaid.transactionsSync({ access_token: ex.access_token, cursor });
      added.push(...data.added);
      cursor = data.next_cursor;
      hasMore = data.has_more;
    }
    console.log(`attempt ${attempt}: ${added.length} transactions`);
    if (added.length === 0) await sleep(3000);
  }

  console.table(added.map((t) => ({
    merchant: t.merchant_name ?? t.name,
    amount: t.amount,
    plaid: t.personal_finance_category?.detailed,
    anchor: categorize(t) ?? "(skipped)",
  })));
} catch (err) {
  console.error(err.response?.data ?? err);
}