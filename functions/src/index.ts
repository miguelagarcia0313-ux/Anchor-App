import {setGlobalOptions} from "firebase-functions";

// Cost control: max containers per function.
setGlobalOptions({maxInstances: 10});

export {
  createLinkToken,
  exchangePublicToken,
  syncTransactions,
} from "./plaid.js";
