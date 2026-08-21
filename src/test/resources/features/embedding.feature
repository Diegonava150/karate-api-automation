@catalog
Feature: Nested resources are assembled and shaped correctly

  # This is the file that justifies choosing Karate for this project.
  #
  # PostgREST reads the foreign keys in init.sql and lets a caller ask for related rows inline,
  # so one request returns an author with their books and each book with its reviews. Asserting
  # on that in an imperative client means a dozen path lookups and a dozen chances to assert on
  # the wrong index. Karate compares the whole document against one shape, in one step, and the
  # failure names the exact path that differs.
  #
  # `#string`, `#number`, `#[]` and friends are Karate's fuzzy matchers: they pin the *shape*
  # without pinning values that legitimately change. That distinction is the point — a test that
  # hardcodes every value fails on every edit and teaches everyone to update it without reading.

  Background:
    * url baseUrl

  Scenario: An author embeds their books, and each book embeds its reviews

    Given path 'authors'
    And param select = '*,books(*,reviews(*))'
    And param id = 'eq.1'
    When method get
    Then status 200

    # One assertion for the entire nested document. Values that are fixtures are pinned;
    # everything else is pinned by type only.
    And match response ==
      """
      [
        {
          id: 1,
          name: 'Ursula K. Le Guin',
          country: 'United States',
          email: 'ursula@example.com',
          books: '#[_ >= 2]'
        }
      ]
      """

    # Not an exact count, for the same reason as books.feature: a create scenario running
    # concurrently attaches another book to this very author, and an exact 2 would make this
    # test fail on a race that is not a defect.
    * def titles = $response[0].books[*].title
    And match titles contains ['The Left Hand of Darkness', 'A Wizard of Earthsea']

    # Every embedded book belongs to this author and carries a well-formed shape.
    And match each response[0].books contains { authorId: 1, isbn: '#regex [0-9]{13}', priceUsd: '#number', pageCount: '#number', inPrint: '#boolean' }

  Scenario: Reviews come back nested inside the book they belong to

    Given path 'books'
    And param select = 'title,reviews(reviewer,rating)'
    And param id = 'eq.1'
    When method get
    Then status 200
    And match response ==
      """
      [
        {
          title: 'The Left Hand of Darkness',
          reviews: [
            { reviewer: 'alex', rating: 5 },
            { reviewer: 'sam',  rating: 4 }
          ]
        }
      ]
      """

  Scenario: A book with no reviews embeds an empty list, not null

    # Worth pinning explicitly. "No related rows" and "the relationship is missing" are
    # different facts, and a client that treats null and [] the same way is one schema change
    # away from a null pointer.
    Given path 'books'
    And param select = 'title,reviews(*)'
    And param id = 'eq.2'
    When method get
    Then status 200
    And match response[0].reviews == []

  Scenario: Filtering on an embedded resource narrows the parent, not just the child

    # PostgREST's `!inner` turns an embed into a join, so authors with no matching book drop
    # out entirely. Easy to get wrong, and the wrong version still returns 200 with plausible
    # data — which is precisely the kind of thing worth a test.
    Given path 'authors'
    # The map form, not `param 'books.inPrint' = ...`. A quoted parameter *name* is sent with
    # its quotes attached, so PostgREST receives a filter on a column called `'books` and
    # answers 400. Verified against the running service: every sane encoding of this query
    # returns 200, so the encoding was never the problem — the step syntax was.
    And params { select: 'name,books!inner(title,inPrint)', 'books.inPrint': 'eq.false' }
    When method get
    Then status 200
    And match response == '#[1]'
    And match response[0].name == 'Italo Calvino'
    And match each response[0].books contains { inPrint: false }

  Scenario Outline: Every seeded author is reachable and correctly shaped

    Given path 'authors'
    And param id = 'eq.<id>'
    When method get
    Then status 200
    And match response[0] == { id: <id>, name: '<name>', country: '<country>', email: '#regex .+@.+\\..+' }

    Examples:
      | id | name                   | country       |
      | 1  | Ursula K. Le Guin      | United States |
      | 2  | Gabriel Garcia Marquez | Colombia      |
      | 3  | Italo Calvino          | Italy         |
