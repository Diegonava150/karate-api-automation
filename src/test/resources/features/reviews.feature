Feature: Reviews are constrained to the ratings a review can actually have

  # The reviews table existed with a CHECK on rating and no test of any kind against it, which
  # is the least defensible kind of gap: a constraint written down, believed, and never once
  # exercised. `rating BETWEEN 1 AND 5` is exactly the sort of rule that survives a schema
  # migration by accident and disappears without anyone noticing.

  Background:
    * url baseUrl

  # ------------------------------------------------------------------ read

  Scenario: List every review
    Given path 'reviews'
    When method get
    Then status 200
    And match response == '#[_ >= 4]'
    And match each response contains { id: '#number', bookId: '#number', reviewer: '#string', rating: '#number' }

  @perf
  Scenario: Reviews can be filtered to one book
    Given path 'reviews'
    And param bookId = 'eq.1'
    And param order = 'rating.desc'
    When method get
    Then status 200
    And match response == '#[2]'
    And match response[*].reviewer contains only ['alex', 'sam']
    And match response[0].rating == 5

  Scenario: Every rating in the seeded data is inside the permitted range

    # Reads as a tautology and is not. It is the assertion that fails the day someone widens
    # the CHECK and backfills a zero, which is a data problem no CRUD scenario would catch.
    Given path 'reviews'
    When method get
    Then status 200
    * def ratings = $response[*].rating
    And match each ratings == '#? _ >= 1 && _ <= 5'

  # ---------------------------------------------------------------- create

  Scenario: Leave a review
    Given path 'reviews'
    And headers returnRepresentation
    And request { bookId: 2, reviewer: 'dana', rating: 4, body: 'Quietly enormous.' }
    And headers writerAuth
    When method post
    Then status 201
    And match response[0] contains { bookId: 2, reviewer: 'dana', rating: 4 }
    * def created = response[0].id

    Given path 'reviews'
    And param id = 'eq.' + created
    And headers writerAuth
    When method delete
    Then status 204

  Scenario: The body is optional and defaults to empty, not null

    # A DEFAULT that is silently dropped turns every "no comment" review into a null the client
    # has to guard. Worth pinning, because the difference only shows up at the caller.
    Given path 'reviews'
    And headers returnRepresentation
    And request { bookId: 2, reviewer: 'terse', rating: 3 }
    And headers writerAuth
    When method post
    Then status 201
    And match response[0].body == ''
    * def created = response[0].id

    Given path 'reviews'
    And param id = 'eq.' + created
    And headers writerAuth
    When method delete
    Then status 204

  @negative
  Scenario Outline: A rating outside one to five is rejected

    # The boundaries are the point, so 1 and 5 are covered above by the seed and here only the
    # values just outside them are exercised. A test that only tries 99 proves the CHECK exists
    # but not where it sits.
    Given path 'reviews'
    And request { bookId: 1, reviewer: 'out-of-range', rating: <rating>, body: '' }
    And headers writerAuth
    When method post
    Then status 400
    And match response.code == '23514'

    Examples:
      | rating |
      | 0      |
      | 6      |
      | -1     |
      | 99     |

  @negative
  Scenario: A review with no reviewer is rejected
    Given path 'reviews'
    And request { bookId: 1, rating: 3, body: '' }
    And headers writerAuth
    When method post
    Then status 400
    And match response.code == '23502'

  @negative
  Scenario: A review whose reviewer is only whitespace is rejected
    Given path 'reviews'
    And request { bookId: 1, reviewer: '   ', rating: 3, body: '' }
    And headers writerAuth
    When method post
    Then status 400
    And match response.code == '23514'

  @negative
  Scenario: A review against a book that does not exist is rejected
    Given path 'reviews'
    And request { bookId: 999999, reviewer: 'ghost', rating: 3, body: '' }
    And headers writerAuth
    When method post
    Then status 409
    And match response.code == '23503'

  # ---------------------------------------------------------------- update

  Scenario: A rating can be corrected within range
    Given path 'reviews'
    And param id = 'eq.2'
    And headers returnRepresentation
    And request { rating: 3 }
    And headers writerAuth
    When method patch
    Then status 200
    And match response[0].rating == 3

    Given path 'reviews'
    And param id = 'eq.2'
    And request { rating: 4 }
    And headers writerAuth
    When method patch
    Then status 204

  @negative
  Scenario: A rating cannot be corrected out of range

    # The CHECK has to hold on UPDATE as well as INSERT. Constraints that are only enforced on
    # the way in are a real and common bug, and nothing about a passing create scenario says
    # anything about it.
    Given path 'reviews'
    And param id = 'eq.2'
    And request { rating: 0 }
    And headers writerAuth
    When method patch
    Then status 400
    And match response.code == '23514'
