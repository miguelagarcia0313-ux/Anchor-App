Feature: Budget pace
  As a user, I want to see my budget pace for each finance category,
  so I know if I'm on or off track before the month ends.

  Background:
    Given the Anchor app is running
    And I am logged in

  Scenario: Category under budget shows normal pace
    Given I have spent $62.40 on "Groceries" this month
    And my monthly budget for "Groceries" is $150.00
    When I open the Finance screen
    Then I should see "Groceries" with spent amount "$62.40"
    And the "Groceries" ring should not be flagged as over pace

  Scenario: Category ahead of expected pace is flagged
    Given I have spent $78.00 on "Eating Out" this month
    And my monthly budget for "Eating Out" is $100.00
    And today is past the point in the month where $78.00 would be expected
    When I open the Finance screen
    Then I should see "Eating Out" with spent amount "$78.00"
    And the "Eating Out" ring should be flagged as over pace

  Scenario: Multiple categories display independently
    Given I have logged expenses in "Groceries", "Eating Out", and "Subscriptions"
    When I open the Finance screen
    Then I should see all three categories listed
    And each category should show its own spent and budget amounts
