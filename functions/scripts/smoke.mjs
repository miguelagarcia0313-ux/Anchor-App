import { Configuration, PlaidApi, PlaidEnvironments, Products } from "plaid";

const plaid = new PlaidApi(new Configuration({
  basePath: PlaidEnvironments.sandbox,
  baseOptions: { headers: {
    "PLAID-CLIENT-ID": process.env.PLAID_CLIENT_ID,
    "PLAID-SECRET": process.env.PLAID_SECRET,
  }},
}));

try {
  const { data: pt } = await plaid.sandboxPublicTokenCreate({
    institution_id: "ins_109508",
    initial_products: [Products.Transactions],
  });
  const { data: ex } = await plaid.itemPublicTokenExchange({ public_token: pt.public_token });
  console.log("item_id:", ex.item_id);

  const { data: sync } = await plaid.transactionsSync({ access_token: ex.access_token });
  console.log("added:", sync.added.length, "has_more:", sync.has_more);
  console.log(sync.added.slice(0, 5).map(t =>
    [t.name, t.amount, t.personal_finance_category?.detailed]));
} catch (err) {
  console.error(err.response?.data ?? err);
}
