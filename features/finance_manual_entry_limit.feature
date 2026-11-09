Feature: Manual expense amount limit
  As a user logging expenses manually
  I want clear feedback when an amount is out of range
  So that my entry isn't silently rejected

  Background:
    Given I am signed in
    And I am on the Finance screen
    And I have opened the manual entry form

  Scenario Outline: Out-of-range amounts are rejected with a message
    When I enter "<amount>" as the amount
    And I tap Save
    Then I should see the amount error "<message>"
    And the manual entry form should still be open

    Examples:
      | amount    | message                                |
      | 1000000   | Manual Entry cannot exceed 100,000     |
      | 100000.01 | Manual Entry cannot exceed 100,000     |
      | 0         | Enter a valid amount greater than $0   |
      | abc       | Enter a valid amount greater than $0   |