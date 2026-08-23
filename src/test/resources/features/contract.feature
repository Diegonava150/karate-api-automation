Feature: The mock and the real service answer the same consumer

  # The point of the whole contract directory.
  #
  # One set of consumer expectations (catalog-consumer.feature) is run twice: against the real
  # containerised PostgREST service, and against the Karate mock that stands in for it. Both
  # must pass. If the provider changes in a way the mock does not follow, the second run keeps
  # passing while the first fails — and the diff between them is the drift.
  #
  # A mock checked only against itself is a fixture with opinions. It agrees with whatever it
  # was written to agree with, forever, and the first thing to notice that it stopped
  # describing reality is production.

  Scenario: the real service satisfies the consumer contract
    * def target = baseUrl
    * def result = call read('classpath:contracts/catalog-consumer.feature') { target: '#(target)' }

  Scenario: the mock satisfies the same consumer contract
    * def target = mockUrl
    * def result = call read('classpath:contracts/catalog-consumer.feature') { target: '#(target)' }
