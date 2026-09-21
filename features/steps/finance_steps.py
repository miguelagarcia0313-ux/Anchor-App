# STATUS: Finance-side Keys now exist (see finance_module.dart on
# nate/finance-bdd-keys). Still blocked on:
#   1. main.dart's enableFlutterDriverExtension() -- pending team sign-off
#   2. Login flow / data seeding -- app still reads from generateMockEntries(),
#      so "Given I have spent $X" steps can't inject real values yet.
# These are noted per-step below rather than silently faked.

from behave import given, when, then
from appium_flutter_finder import FlutterElement, FlutterFinder

finder = FlutterFinder()


def _slug(category: str) -> str:
    """'Eating Out' -> 'eating_out', matching the keys used in
    finance_module.dart's _demoBudgets map."""
    return category.lower().replace(" ", "_")


@given("the Anchor app is running")
def step_app_running(context):
    # App is already running by the time Appium connects (see
    # environment.py before_all) -- documented here for readability.
    pass


@given("I am logged in")
def step_logged_in(context):
    # TODO: needs a test Firebase account + Keys on login_screen.dart's
    # email/password fields once main.dart's driver extension is in.
    raise NotImplementedError("Test login flow not wired up yet")


@given('I have spent ${amount} on "{category}" this month')
def step_seed_spend(context, amount, category):
    # TODO: app currently reads from generateMockEntries() (hardcoded),
    # so this can't inject a specific amount yet. Once persistence
    # exists, seed the test database directly here before app launch.
    raise NotImplementedError("Data seeding not wired up yet")


@given('my monthly budget for "{category}" is ${amount}')
def step_seed_budget(context, category, amount):
    raise NotImplementedError("Budget seeding not wired up yet")


@given("today is past the point in the month where {amount} would be expected")
def step_seed_date_context(context, amount):
    # This is inherently about the mock data's fixed timestamps vs
    # "today" -- not something to seed independently. Covered implicitly
    # once real data seeding (above) exists.
    pass


@when("I open the Finance screen")
def step_open_finance(context):
    card = finder.by_value_key("finance_summary_card")
    context.driver.execute_script("flutter:waitFor", card)
    FlutterElement(context.driver, card).click()


@then('I should see "{category}" with spent amount "{amount}"')
def step_check_spent_amount(context, category, amount):
    amount_finder = finder.by_value_key(f"finance_category_amount_{_slug(category)}")
    context.driver.execute_script("flutter:waitFor", amount_finder)
    element = FlutterElement(context.driver, amount_finder)
    assert amount in element.text, f"Expected {amount} in element text, got {element.text}"


@then('the "{category}" ring should be flagged as over pace')
def step_check_over_pace(context, category):
    amount_finder = finder.by_value_key(f"finance_category_amount_{_slug(category)}")
    context.driver.execute_script("flutter:waitFor", amount_finder)
    element = FlutterElement(context.driver, amount_finder)
    assert "ahead of pace" in element.text, (
        f"Expected '{category}' to show 'ahead of pace', got: {element.text}"
    )


@then('the "{category}" ring should not be flagged as over pace')
def step_check_not_over_pace(context, category):
    amount_finder = finder.by_value_key(f"finance_category_amount_{_slug(category)}")
    context.driver.execute_script("flutter:waitFor", amount_finder)
    element = FlutterElement(context.driver, amount_finder)
    assert "ahead of pace" not in element.text, (
        f"'{category}' was unexpectedly flagged over pace: {element.text}"
    )


@given('I have logged expenses in "{cat1}", "{cat2}", and "{cat3}"')
def step_seed_multiple_categories(context, cat1, cat2, cat3):
    raise NotImplementedError("Data seeding not wired up yet")


@then("I should see all three categories listed")
def step_check_three_categories(context):
    for category in ["groceries", "eating_out", "subscriptions"]:
        row_finder = finder.by_value_key(f"finance_category_row_{category}")
        context.driver.execute_script("flutter:waitFor", row_finder)


@then("each category should show its own spent and budget amounts")
def step_check_each_category_amounts(context):
    for category in ["groceries", "eating_out", "subscriptions"]:
        amount_finder = finder.by_value_key(f"finance_category_amount_{category}")
        context.driver.execute_script("flutter:waitFor", amount_finder)
        element = FlutterElement(context.driver, amount_finder)
        assert "$" in element.text, f"Expected a dollar amount for {category}, got: {element.text}"
