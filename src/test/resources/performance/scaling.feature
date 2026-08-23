Feature: Cost grows with the result set, and no faster

  # The other kind of performance assertion that survives a shared runner: a ratio.
  #
  # Both measurements happen in the same run, on the same machine, seconds apart — so whatever
  # the runner's speed happens to be that morning, it divides out. What is left is the *shape* of
  # the curve, which is a property of the code and not of the hardware.
  #
  # That is what catches the failures worth catching. An N+1, a missing index on a join, an
  # accidental quadratic: all of them show up as cost growing faster than the result set, and
  # none of them needs an absolute number to detect.
  #
  # Sizing the bound, which the first version of this file got wrong.
  #
  #     limit=100      5.4 ms
  #     limit=1000     9.0 ms      10x the rows, 1.7x the time
  #     limit=10000   29.8 ms      10x the rows, 3.3x the time
  #
  # Per-row cost falls as the page grows, which is the healthy shape — fixed overhead amortised
  # over more rows. The first bound was eight, chosen against a locally observed 1.4, and it was
  # wrong in a way worth recording: **linear scaling is a ratio of ten**. A bound of eight
  # asserts that the endpoint is strictly *sub*-linear, which no correct system owes anyone. It
  # held locally only because a five-millisecond fixed cost dominated a four-millisecond query.
  #
  # The first CI run measured 5 where the laptop measured 1.4 — over half the budget spent by a
  # perfectly healthy system on a machine with less overhead to hide behind. A faster runner
  # would have failed the build for scaling correctly.
  #
  # So the bound is twenty. Above linear, with room for a noisy runner; far below what the
  # failures worth catching actually look like, since an N+1 or a missing join index turns ten
  # times the rows into fifty or a hundred times the time, not eleven.
  #
  # The pages are also larger than they were. At a one-millisecond timer resolution a 1 ms
  # baseline carries a 100% error bar, and the ratio inherits it.

  Background:
    * url baseUrl

    # One throwaway request first. The very first call of a run pays for connection setup and JIT
    # that no later call pays, and folding that into the baseline makes the ratio look better
    # than it is — which is the wrong direction for a test to be wrong in.
    * path 'books'
    * param limit = 1
    * method get

  Scenario: Ten times the rows does not cost fifty times the time

    Given path 'books'
    And param limit = 1000
    When method get
    Then status 200
    And match response == '#[1000]'
    * def smallPage = responseTime

    Given path 'books'
    And param limit = 10000
    When method get
    Then status 200
    And match response == '#[10000]'
    * def largePage = responseTime

    * def ratio = largePage / Math.max(smallPage, 1)
    * karate.log('1000 rows:', smallPage, 'ms   10000 rows:', largePage, 'ms   ratio:', ratio)

    # Linear is 10. This permits linear plus a wide margin for a noisy runner, and still fails
    # long before an N+1 or a missing join index, which land at fifty or worse.
    And assert ratio <= 20

  Scenario: An embedded read does not cost more per parent as the page grows

    # The N+1 detector proper. If reviews were fetched one query per book, twenty books would
    # cost roughly ten times what two books cost. They should not.
    Given path 'books'
    And params { select: '*,reviews(*)', limit: 2 }
    When method get
    Then status 200
    * def few = responseTime

    Given path 'books'
    And params { select: '*,reviews(*)', limit: 20 }
    When method get
    Then status 200
    * def many = responseTime

    * def ratio = many / Math.max(few, 1)
    * karate.log('2 embedded:', few, 'ms   20 embedded:', many, 'ms   ratio:', ratio)

    # Ten times the parents. Linear is 10; a query per parent is what this is looking for, and
    # that shows up far above 20.
    And assert ratio <= 20
