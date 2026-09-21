# NOTE: calculateSavingsProjection() exists in insights_calculations.dart and
# is tested at the unit level (test/insights_calculations_test.dart), but the
# UI to display this on-screen has not been built yet. These scenarios are
# written ahead of the UI so they can guide that work -- they will fail
# against the current app until a Savings Projection screen exists.

Feature: Savings projection
  As a user, I want to see a savings projection if I cut discretionary
  categories for a set number of months, so I can decide whether it's
  worth changing my habits.

  Background:
    Given the Anchor app is running
    And I am logged in

  Scenario: Projecting savings from one discretionary category
    Given "Eating Out" is flagged as a discretionary category
    And I have spent $78.00 on "Eating Out" in the last 30 days
    When I open the Savings Projection screen
    And I select "Eating Out" as a category to cut
    And I set the projection period to 2 months
    Then I should see a projected savings amount greater than $0

  Scenario: Projecting savings from multiple discretionary categories
    Given "Eating Out" and "Entertainment" are flagged as discretionary
    And I have spent $78.00 on "Eating Out" and $42.00 on "Entertainment" in the last 30 days
    When I open the Savings Projection screen
    And I select both "Eating Out" and "Entertainment" to cut
    And I set the projection period to 2 months
    Then the projected savings should reflect both categories combined
