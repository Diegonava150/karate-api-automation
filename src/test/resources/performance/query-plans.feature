Feature: The database reaches rows the way it is supposed to

  # Performance assertions with no clock in them.
  #
  # PostgREST will return the query plan instead of the rows when asked for
  # `application/vnd.pgrst.plan`, so this file asserts on how the database *reaches* the data
  # rather than on how long it took. That distinction is the entire point: a timing threshold on
  # a shared CI runner is either loose enough never to fire or tight enough to fire at random,
  # while "this lookup uses an index" is the same answer on every machine that has ever existed.
  #
  # It only means anything at volume. Against the ordinary eleven-row seed Postgres declines to
  # use an index — correctly, because scanning four rows is cheaper than consulting a tree — so
  # every plan here would assert the opposite of the truth. These scenarios run against
  # db/volume.sql: ten thousand books, fifty thousand reviews.
  #
  # This file found a real defect on the day it was written. Postgres indexes a PRIMARY KEY and a
  # UNIQUE constraint automatically and does *not* index the referencing side of a FOREIGN KEY —
  # which is the side every child lookup filters on. `/reviews?bookId=eq.500` was a sequential
  # scan of fifty thousand rows, costing 993 to return five. The same plan against the small seed
  # showed nothing wrong at all.

  Background:
    * url baseUrl
    * configure headers = { Accept: 'application/vnd.pgrst.plan' }

  Scenario: A primary key lookup uses the primary key

    # The control. If this ever stops being an index scan, the problem is not indexing — it is
    # that plan output has silently stopped working and every other scenario here is asserting
    # against an empty string.
    Given path 'books'
    And param id = 'eq.500'
    When method get
    Then status 200
    And match response contains 'Index Scan using books_pkey'

  Scenario: Reviews filtered by their book do not scan the whole table

    # The defect this file was written to catch. Fifty thousand reviews, five of them wanted.
    # Without books_book_idx this is `Seq Scan on reviews` at a cost of 993; with it, a bitmap
    # scan at 22.
    Given path 'reviews'
    And param bookId = 'eq.500'
    When method get
    Then status 200
    And match response !contains 'Seq Scan on reviews'

  Scenario: Books filtered by their author do not scan the whole table
    Given path 'books'
    And param authorId = 'eq.100'
    When method get
    Then status 200
    And match response !contains 'Seq Scan on books'

  Scenario: An embedded read is one statement, not one per parent

    # The failure mode every ORM has and every API inherits: a request that looks like one query
    # and issues N. PostgREST compiles an embed into a single statement with nested loops, and
    # this asserts that it has stayed that way — a plan is by definition one statement, so the
    # thing worth pinning is that the children are reached by index rather than re-scanned for
    # every parent.
    Given path 'authors'
    And params { select: '*,books(*,reviews(*))', limit: 20 }
    When method get
    Then status 200
    And match response contains 'Nested Loop'
    And match response !contains 'Seq Scan on reviews'

  Scenario: Ordering by a column the API exposes does not sort the whole table in memory

    # Not currently indexed, and deliberately not asserted as such — this pins the weaker
    # property that the planner is not resorting to an external merge on disk, which is the
    # symptom that actually shows up as a latency cliff.
    Given path 'books'
    And params { order: 'priceUsd.desc', limit: 50 }
    When method get
    Then status 200
    And match response !contains 'external merge'
