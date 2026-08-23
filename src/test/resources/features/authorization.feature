Feature: Reads are open, writes are not

  # PostgREST does not decide authorisation itself. A token names a Postgres role, PostgREST
  # switches the session to it, and the GRANTs in init.sql decide the rest. So these scenarios
  # are testing the schema's permission model over HTTP, which is the only place a caller can
  # actually observe it.
  #
  # Written after the fact, and the writing found something: adding the writer token to every
  # write was mechanical, and mechanical changes are exactly the ones that pass without doing
  # anything. Removing the token from a single create scenario produced 401 where 201 was
  # expected, which is the only reason the other thirty-nine headers are known to matter.

  Background:
    * url baseUrl

  # ------------------------------------------------------- anonymous is read-only

  Scenario: Anyone may read the catalogue without a token
    Given path 'books'
    When method get
    Then status 200
    And match response == '#[_ >= 4]'

  @negative
  Scenario Outline: An anonymous write is refused

    # 401, not 403. PostgREST answers "unauthenticated" when there is no token at all, and the
    # distinction is worth pinning: a client that retries on 403 and re-authenticates on 401
    # behaves differently for each, and getting them the wrong way round produces a retry loop.
    Given path '<resource>'
    And request <body>
    When method <verb>
    Then status 401

    Examples:
      | resource | verb   | body                                                                                                            |
      | books    | post   | { title: 'Anon', authorId: 1, isbn: '9780000000101', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }    |
      | authors  | post   | { name: 'Anon', country: 'Nowhere', email: 'anon@example.com' }                                                 |
      | reviews  | post   | { bookId: 1, reviewer: 'anon', rating: 3, body: '' }                                                            |

  @negative
  Scenario: An anonymous delete is refused
    Given path 'books'
    And param id = 'eq.1'
    When method delete
    Then status 401

  # ------------------------------------------------- a valid token is not a blank cheque

  Scenario: A reader token can read
    Given path 'books'
    And headers readerAuth
    When method get
    Then status 200
    And match response == '#[_ >= 4]'

  @negative
  Scenario Outline: A reader token cannot write

    # The bug this exists for is not "anonymous users can write" — that one is obvious and
    # usually caught. It is a valid, authenticated token whose role was granted more than anyone
    # intended, which looks exactly like a working request until someone audits the GRANTs.
    #
    # 403 here rather than 401: the caller is authenticated and simply not permitted.
    Given path '<resource>'
    And headers readerAuth
    And request <body>
    When method <verb>
    Then status 403

    Examples:
      | resource | verb   | body                                                                                                            |
      | books    | post   | { title: 'Reader', authorId: 1, isbn: '9780000000102', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }  |
      | reviews  | post   | { bookId: 1, reviewer: 'reader', rating: 3, body: '' }                                                          |

  @negative
  Scenario: A reader token cannot delete
    Given path 'books'
    And headers readerAuth
    And param id = 'eq.1'
    When method delete
    Then status 403

  # ------------------------------------------------------------ bad tokens

  @negative
  Scenario: An expired token is refused
    Given path 'books'
    And headers expiredAuth
    And request { title: 'Expired', authorId: 1, isbn: '9780000000103', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }
    When method post
    Then status 401

  @negative
  Scenario: A token signed with the wrong key is refused

    # Distinct from the garbled string below, and the more important of the two. This token
    # parses, carries a plausible role and a valid expiry, and is refused purely because the
    # signature does not verify. A suite that only sends nonsense proves the parser works, not
    # that anything checks who signed it.
    Given path 'books'
    And headers forgedAuth
    And request { title: 'Forged', authorId: 1, isbn: '9780000000104', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }
    When method post
    Then status 401

  @negative
  Scenario: A malformed token is refused
    Given path 'books'
    And header Authorization = 'Bearer not-a-token'
    And request { title: 'Malformed', authorId: 1, isbn: '9780000000105', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }
    When method post
    Then status 401

  @negative
  Scenario: A reader token cannot be used to escalate by asking for a different role

    # The role comes from the signed claim, not from anything the caller can set alongside it.
    # Worth an explicit test because a header-driven role switch is a plausible-looking design
    # that would be catastrophic, and its absence is invisible otherwise.
    Given path 'books'
    And headers readerAuth
    And header Role = 'catalog_writer'
    And request { title: 'Escalated', authorId: 1, isbn: '9780000000106', priceUsd: 1.00, pageCount: 1, published: '2020-01-01' }
    When method post
    Then status 403
