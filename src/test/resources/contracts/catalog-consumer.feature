Feature: What a consumer of the catalog API relies on

  # Lives outside `features/` on purpose, so the runner cannot sweep it up and execute it
  # directly. It is called twice by features/contract.feature — once against the real service
  # and once against the mock — with `target` set to whichever is under test.
  #
  # A tag would have done the same job and did not: `@ignore` plus `~@ignore` on the runner
  # left it running anyway, and four scenarios failed for want of a `target` that only a caller
  # can supply. Directory layout is not subject to tag-inheritance rules.
  #
  # This file is the contract. It contains only the promises a caller actually depends on, and
  # deliberately not everything the API can do: a contract that restates the whole
  # implementation pins the provider in place and stops being a contract.
  #
  # Shapes, not values. `#string` and `#number` say "this field exists and is of this type",
  # which is what a consumer breaks on. Pinning the seeded price would make the mock and the
  # database disagree the first time anyone edits a fixture, and that failure would say nothing
  # about the contract.

  Background:
    * url target

  Scenario: A consumer can list books and read the fields it renders

    Given path 'books'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And match each response contains
      """
      {
        id: '#number',
        title: '#string',
        isbn: '#regex [0-9]{13}',
        priceUsd: '#number',
        inPrint: '#boolean'
      }
      """

  Scenario: A consumer can fetch one book with its author inline

    # The single request that saves a client from an N+1. If the provider ever stops supporting
    # the embed, every consumer doing this breaks — which is exactly what a contract is for.
    Given path 'books'
    And param select = '*,author:authors(name,country)'
    And param id = 'eq.1'
    When method get
    Then status 200
    And match response == '#[1]'
    And match response[0] contains
      """
      {
        id: 1,
        title: '#string',
        author: { name: '#string', country: '#string' }
      }
      """

  Scenario: A missing book is an empty list and not an error

    # The behaviour most likely to be "helpfully" changed to a 404 by a provider who has not
    # met the consumers. Written down so that change cannot happen quietly.
    Given path 'books'
    And param id = 'eq.999999'
    When method get
    Then status 200
    And match response == []

  Scenario: A consumer can list authors and read the fields it renders

    # The catalogue UI shows an author beside every book, so the author list is as much a
    # dependency as the book list. It was not in the contract, which meant the mock was free to
    # know nothing about authors at all and still be declared in agreement with the provider.
    Given path 'authors'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And match each response contains
      """
      {
        id: '#number',
        name: '#string',
        country: '#string'
      }
      """

  Scenario: A consumer can fetch the reviews for one book

    # Filtered by the parent id, which is the only way a client ever asks for reviews. Asserting
    # the unfiltered list would let the provider drop filtering entirely and still pass.
    Given path 'reviews'
    And param bookId = 'eq.1'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And match each response contains
      """
      {
        id: '#number',
        bookId: 1,
        reviewer: '#string',
        rating: '#? _ >= 1 && _ <= 5'
      }
      """

  Scenario: Reviews for a book with none is an empty list

    # Same promise as the missing book above, one resource along. A client that renders a review
    # count breaks on null and not on [].
    Given path 'reviews'
    And param bookId = 'eq.999999'
    When method get
    Then status 200
    And match response == []

  Scenario: A rejected write explains itself with a machine-readable code

    # Consumers branch on this. A 400 alone forces string-matching on a human message, which is
    # the thing that breaks on a library upgrade.
    Given path 'books'
    And request { title: 'Contract Probe', authorId: 1, isbn: '9780441478125', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }
    When method post
    Then status 409
    And match response contains { code: '23505' }
