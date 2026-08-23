Feature: Authors are unique by email and cannot be blank

  # The authors table was reachable only through embedding — read as a side effect of asking for
  # books, never written to, and its constraints never exercised. init.sql even carried the
  # comment "UNIQUE gives the negative suite a real 409, and the CHECK a real 400", describing a
  # negative suite that did not exist. A comment asserting behaviour nobody tests is worse than
  # no comment: it reads as evidence.

  Background:
    * url baseUrl

  # ------------------------------------------------------------------ read

  @perf
  Scenario: List every author
    Given path 'authors'
    And param order = 'id.asc'
    When method get
    Then status 200
    And match response == '#[_ >= 3]'
    And match each response contains { id: '#number', name: '#string', country: '#string', email: '#regex .+@.+\\..+' }

  Scenario: Authors can be filtered by country
    Given path 'authors'
    And param country = 'eq.Colombia'
    When method get
    Then status 200
    And match response == '#[1]'
    And match response[0].name == 'Gabriel Garcia Marquez'

  # ---------------------------------------------------------------- create

  Scenario: Add an author
    Given path 'authors'
    And headers returnRepresentation
    And request { name: 'Octavia E. Butler', country: 'United States', email: 'octavia@example.com' }
    When method post
    Then status 201
    And match response[0] contains { name: 'Octavia E. Butler', country: 'United States' }
    * def created = response[0].id

    Given path 'authors'
    And param id = 'eq.' + created
    When method delete
    Then status 204

  @negative
  Scenario: An author with a duplicate email is rejected
    Given path 'authors'
    And request { name: 'Not Ursula', country: 'Elsewhere', email: 'ursula@example.com' }
    When method post
    Then status 409
    And match response.code == '23505'

  @negative
  Scenario Outline: An email that is not an email is rejected

    # `email LIKE '%@%.%'` is a deliberately weak check — it is not RFC validation and does not
    # pretend to be. These cases are the ones it actually claims to catch, and pinning them keeps
    # someone from quietly "improving" the constraint into something that rejects real addresses.
    Given path 'authors'
    And request { name: 'Bad Email', country: 'Nowhere', email: '<email>' }
    When method post
    Then status 400
    And match response.code == '23514'

    Examples:
      | email            |
      | not-an-email     |
      | missing-at.co    |
      | no-dot@example   |

  @negative
  Scenario: An author with no name is rejected
    Given path 'authors'
    And request { country: 'Nowhere', email: 'nameless@example.com' }
    When method post
    Then status 400
    And match response.code == '23502'

  @negative
  Scenario: An author whose name is only whitespace is rejected
    Given path 'authors'
    And request { name: '   ', country: 'Nowhere', email: 'blank@example.com' }
    When method post
    Then status 400
    And match response.code == '23514'

  @negative
  Scenario: An author with no country is rejected
    Given path 'authors'
    And request { name: 'Stateless', email: 'stateless@example.com' }
    When method post
    Then status 400
    And match response.code == '23502'

  # ---------------------------------------------------------------- update

  @negative
  Scenario: An author cannot be updated into a duplicate email

    # The unique index has to hold on UPDATE as well as INSERT, and nothing about a passing
    # create scenario says that it does.
    Given path 'authors'
    And param id = 'eq.2'
    And request { email: 'ursula@example.com' }
    When method patch
    Then status 409
    And match response.code == '23505'

  # ---------------------------------------------------------------- delete

  Scenario: Deleting an author takes their books, and the reviews of those books

    # Two cascades in a row: authors -> books -> reviews. The second hop is the one worth
    # asserting, because a schema that cascades one level and orphans the next looks correct
    # from the parent and leaves rows pointing at nothing.
    Given path 'authors'
    And headers returnRepresentation
    And request { name: 'Ephemeral', country: 'Nowhere', email: 'ephemeral@example.com' }
    When method post
    Then status 201
    * def authorId = response[0].id

    Given path 'books'
    And headers returnRepresentation
    And request { title: 'Doomed', authorId: '#(authorId)', isbn: '9780000000009', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }
    When method post
    Then status 201
    * def bookId = response[0].id

    Given path 'reviews'
    And request { bookId: '#(bookId)', reviewer: 'doomed', rating: 3, body: '' }
    When method post
    Then status 201

    Given path 'authors'
    And param id = 'eq.' + authorId
    When method delete
    Then status 204

    Given path 'books'
    And param id = 'eq.' + bookId
    When method get
    Then status 200
    And match response == []

    Given path 'reviews'
    And param bookId = 'eq.' + bookId
    When method get
    Then status 200
    And match response == []
