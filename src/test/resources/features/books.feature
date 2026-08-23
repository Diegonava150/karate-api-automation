Feature: Books can be read, created, changed and deleted

  # Every happy path here has a negative counterpart, and the negatives assert on SQLSTATE
  # codes rather than on a bare status. That distinction matters: 400 says "something was
  # wrong", 23514 says "a CHECK constraint rejected this", and only the second one survives a
  # refactor that changes how errors are surfaced.
  #
  # Those codes are real. They come from Postgres rejecting the write, not from a mock told to
  # return a number, which is the whole reason the suite starts its own database.

  Background:
    * url baseUrl

  # ------------------------------------------------------------------ read

  @perf
  Scenario: List every book

    # `#[_ >= 4]`, not `#[4]`, and this is not hedging.
    #
    # The suite runs four scenarios at a time, and two of them create books. An exact count
    # asserts that nothing else is happening, which is false by construction here — the first
    # run of this file failed with "actual array length is 5" and a stray row titled
    # "Temporary" belonging to the cascade-delete scenario two hundred lines below.
    #
    # The fix is to assert what is actually being claimed: the seeded catalogue is present and
    # every row is well formed. Serialising the suite to make an exact count true would trade a
    # real property of the system under test for a tidier number.
    Given path 'books'
    When method get
    Then status 200
    And match response == '#[_ >= 4]'
    And match each response contains { id: '#number', title: '#string', isbn: '#regex [0-9]{13}' }
    * def titles = $response[*].title
    And match titles contains ['The Left Hand of Darkness', 'A Wizard of Earthsea', 'One Hundred Years of Solitude', 'Invisible Cities']

  @perf
  Scenario: Read one book by id
    Given path 'books'
    And param id = 'eq.3'
    When method get
    Then status 200
    And match response[0] contains { title: 'One Hundred Years of Solitude', pageCount: 417 }

  Scenario: Reading a book that does not exist returns an empty list, not an error

    # A missing row is not an error in PostgREST — the filter matched nothing, and an empty
    # result set is a perfectly good answer to "give me the rows where id = 999999". Asserting
    # 404 here would be asserting some other API's behaviour.
    Given path 'books'
    And param id = 'eq.999999'
    When method get
    Then status 200
    And match response == []

  @perf
  Scenario: Order and limit are honoured
    Given path 'books'
    And param order = 'priceUsd.desc'
    And param limit = 2
    When method get
    Then status 200
    And match response == '#[2]'
    * def prices = $response[*].priceUsd
    And assert prices[0] >= prices[1]

  # ---------------------------------------------------------------- create

  Scenario: Create a book
    Given path 'books'
    And headers returnRepresentation
    And request { title: 'The Dispossessed', authorId: 1, isbn: '9780061054884', priceUsd: 15.75, pageCount: 387, published: '1974-05-01', inPrint: true }
    And headers writerAuth
    When method post
    Then status 201
    And match response[0] contains { title: 'The Dispossessed', authorId: 1, pageCount: 387 }
    * def created = response[0].id

    # Clean up after itself so the row count assertions above stay true on a re-run against a
    # warm container.
    Given path 'books'
    And param id = 'eq.' + created
    And headers writerAuth
    When method delete
    Then status 204

  @negative
  Scenario: Creating a book without a required field is rejected
    Given path 'books'
    And request { authorId: 1, isbn: '9780000000001', priceUsd: 9.99, pageCount: 100, published: '2020-01-01' }
    And headers writerAuth
    When method post
    Then status 400
    And match response.code == '23502'

  @negative
  Scenario: Creating a book with a duplicate ISBN is rejected
    Given path 'books'
    And request { title: 'Impostor', authorId: 1, isbn: '9780441478125', priceUsd: 9.99, pageCount: 100, published: '2020-01-01' }
    And headers writerAuth
    When method post
    Then status 409
    And match response.code == '23505'

  @negative
  Scenario: Creating a book with a negative price is rejected
    Given path 'books'
    And request { title: 'Free Money', authorId: 1, isbn: '9780000000002', priceUsd: -0.01, pageCount: 100, published: '2020-01-01' }
    And headers writerAuth
    When method post
    Then status 400
    And match response.code == '23514'

  @negative
  Scenario: Creating a book with no pages is rejected
    Given path 'books'
    And request { title: 'Empty', authorId: 1, isbn: '9780000000003', priceUsd: 5.00, pageCount: 0, published: '2020-01-01' }
    And headers writerAuth
    When method post
    Then status 400
    And match response.code == '23514'

  @negative
  Scenario: Creating a book against an author who does not exist is rejected

    # The foreign key is load-bearing for the embedding scenarios, so it is worth a test of its
    # own rather than being assumed to exist because a join happened to work.
    Given path 'books'
    And request { title: 'Orphan', authorId: 999999, isbn: '9780000000004', priceUsd: 5.00, pageCount: 10, published: '2020-01-01' }
    And headers writerAuth
    When method post
    Then status 409
    And match response.code == '23503'

  # ---------------------------------------------------------------- update

  Scenario: Update a book

    # PATCH with a filter, not PUT. PostgREST has no notion of replacing a row at a URL; the
    # filter is what selects the target, and a PATCH with no filter would rewrite every row in
    # the table.
    Given path 'books'
    And param id = 'eq.2'
    And headers returnRepresentation
    And request { priceUsd: 12.99 }
    And headers writerAuth
    When method patch
    Then status 200
    And match response[0].priceUsd == 12.99

    # Put it back, so the suite is order-independent.
    Given path 'books'
    And param id = 'eq.2'
    And request { priceUsd: 11.50 }
    And headers writerAuth
    When method patch
    Then status 204

  Scenario: Updating a book that does not exist changes nothing
    Given path 'books'
    And param id = 'eq.999999'
    And headers returnRepresentation
    And request { priceUsd: 1.00 }
    And headers writerAuth
    When method patch
    Then status 200
    And match response == []

  @negative
  Scenario: Updating a book into a duplicate ISBN is rejected
    Given path 'books'
    And param id = 'eq.2'
    And request { isbn: '9780441478125' }
    And headers writerAuth
    When method patch
    Then status 409
    And match response.code == '23505'

  # ---------------------------------------------------------------- delete

  Scenario: Deleting a book that does not exist still succeeds

    # Idempotent by design: DELETE says "ensure this is gone", and it is gone.
    Given path 'books'
    And param id = 'eq.999999'
    And headers writerAuth
    When method delete
    Then status 204

  Scenario: Deleting a book takes its reviews with it

    # ON DELETE CASCADE, asserted rather than assumed. The alternative — orphaned reviews
    # pointing at a book that no longer exists — is invisible until something tries to embed
    # them.
    Given path 'books'
    And headers returnRepresentation
    And request { title: 'Temporary', authorId: 2, isbn: '9780000000005', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }
    And headers writerAuth
    When method post
    Then status 201
    * def bookId = response[0].id

    Given path 'reviews'
    And request { bookId: '#(bookId)', reviewer: 'temp', rating: 3, body: 'to be cascaded' }
    And headers writerAuth
    When method post
    Then status 201

    Given path 'books'
    And param id = 'eq.' + bookId
    And headers writerAuth
    When method delete
    Then status 204

    Given path 'reviews'
    And param bookId = 'eq.' + bookId
    When method get
    Then status 200
    And match response == []
