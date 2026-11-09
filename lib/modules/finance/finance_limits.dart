/// Maximum allowed amount for a single manually entered expense.
///
/// MUST match firestore.rules (users/{uid}/expenses create rule):
///   request.resource.data.amount <= <100000>
/// If you change one, change the other, then redeploy the rules.
const double kMaxManualExpense = 100000; // set to your final cap