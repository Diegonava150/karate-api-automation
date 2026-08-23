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
  # Measured before these thresholds were chosen, against ten thousand books:
  #
  #     limit=10     4.9 ms   495 us/row
  #     limit=100    5.3 ms    53 us/row
  #     limit=1000   7.6 ms     8 us/row
  #
  # Per-row cost *falls* as the page grows, which is the healthy shape — fixed overhead being
  # amortised over more rows. Ten times the rows costs 1.4 times the time, so the bound below
  # sits at eight and has a very wide margin. Deliberately: a real N+1 announces itself at
  # tenfold or worse, and a threshold tuned to the observed 1.4 would fail on a busy runner
  # every other week and teach everyone to rerun it.

  Background:
    * url baseUrl

    # One throwaway request first. The very first call of a run pays for connection setup and JIT
    # that no later call pays, and folding that into the baseline makes the ratio look better
    # than it is — which is the wrong direction for a test to be wrong in.
    * path 'books'
    * param limit = 1
    * method get

  Scenario: Ten times the rows does not cost ten times the time

    Given path 'books'
    And param limit = 100
    When method get
    Then status 200
    And match response == '#[100]'
    * def smallPage = responseTime

    Given path 'books'
    And param limit = 1000
    When method get
    Then status 200
    And match response == '#[1000]'
    * def largePage = responseTime

    * def ratio = largePage / Math.max(smallPage, 1)
    * karate.log('100 rows:', smallPage, 'ms   1000 rows:', largePage, 'ms   ratio:', ratio)

    # Linear would be 10. Anything at or below 8 is linear-or-better with room for noise;
    # anything above it means the per-row cost is climbing, which is the signal.
    And assert ratio <= 8

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

    And assert ratio <= 8
