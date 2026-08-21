Feature: A stand-in for the catalog API

  # A Karate mock is a feature file, which is the reason this project is written in Karate at
  # all. The mock and the tests are the same language, so the thing standing in for the
  # provider is reviewable by anyone who can read the suite.
  #
  # What makes it worth having is contract.feature, which runs one set of consumer expectations
  # against this mock *and* against the real containerised service and requires both to pass.
  # A mock that is only ever checked against itself is a fixture with opinions: it drifts the
  # moment the provider changes, keeps passing, and the first thing to notice is production.
  #
  # The sibling REST Assured project documents this exact gap under "Deliberately not covered":
  # provider-side self-consistency is not the same claim as a consumer-driven contract. This is
  # the missing half.
  #
  # Two Karate details this file was written wrong against first, worth knowing before editing:
  #
  #   - `* def x = ...` consumes a single line. A ternary broken across three lines silently
  #     assigns only the first, which produced a boolean `response` and the wonderfully opaque
  #     "unsupported response body type: true". Multi-line expressions need a docstring.
  #   - Karate's JS engine has no String.contains. It is `includes`, or `indexOf(..) >= 0`.

  Background:
    * def books =
      """
      [
        { id: 1, title: 'The Left Hand of Darkness', authorId: 1, isbn: '9780441478125', priceUsd: 14.99, pageCount: 304, published: '1969-03-01', inPrint: true },
        { id: 2, title: 'A Wizard of Earthsea',      authorId: 1, isbn: '9780553383041', priceUsd: 11.50, pageCount: 208, published: '1968-11-01', inPrint: true }
      ]
      """
    * def authorsById = { '1': { name: 'Ursula K. Le Guin', country: 'United States' } }

    # Nothing request-dependent belongs here. A mock's Background is evaluated once, when the
    # server starts, so paramExists/paramValue/request are simply not defined yet — the error
    # is "paramExists is not defined" on every single request, which reads like a version
    # problem and is actually a lifecycle one.
    * def selectedBooks =
      """
      function(params) {
        if (!params || !params.id) return books;
        var raw = params.id[0];
        var wanted = parseInt(('' + raw).replace('eq.', ''));
        return karate.filter(books, function(b){ return b.id == wanted });
      }
      """

  Scenario: methodIs('post') && pathMatches('/books')

    # Only the rejection path is modelled in detail. The consumer contract asserts that a
    # duplicate ISBN comes back as 409 carrying SQLSTATE 23505, and that is the promise worth
    # standing in for.
    * def duplicates = karate.filter(books, function(b){ return b.isbn == request.isbn })
    * def isDuplicate = duplicates.length > 0
    * def responseStatus = isDuplicate ? 409 : 201
    * def conflict = { code: '23505', details: null, hint: null, message: 'duplicate key value violates unique constraint "books_isbn_key"' }
    * def created =
      """
      [{
        id: 99,
        title: request.title,
        authorId: request.authorId,
        isbn: request.isbn,
        priceUsd: request.priceUsd,
        pageCount: request.pageCount,
        published: request.published,
        inPrint: true
      }]
      """
    * def response = isDuplicate ? conflict : created

  Scenario: pathMatches('/books') && paramExists('select') && paramValue('select').includes('authors')

    # The embedded form. Ordered before the plain GET because Karate takes the first scenario
    # whose expression matches.
    * def matching = selectedBooks(requestParams)
    * def withAuthor =
      """
      karate.map(matching, function(b){
        var copy = karate.merge(b, {});
        copy.author = authorsById['' + b.authorId];
        return copy;
      })
      """
    * def responseStatus = 200
    * def response = withAuthor

  Scenario: pathMatches('/books')

    * def responseStatus = 200
    * def response = selectedBooks(requestParams)

  Scenario:

    # Anything unmodelled is a loud 404 rather than a quiet empty body, so a consumer
    # expectation reaching an endpoint the mock does not implement fails visibly instead of
    # looking like "no results".
    * def responseStatus = 404
    * def response = { error: 'not mocked by catalog-mock.feature', path: '#(requestUri)' }
