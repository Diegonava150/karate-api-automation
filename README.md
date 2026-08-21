# Karate API automation — hermetic, with a contract the mock cannot fake

[![CI](https://github.com/Diegonava150/karate-api-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/Diegonava150/karate-api-automation/actions/workflows/ci.yml)
[![Java 21](https://img.shields.io/badge/Java-21-007396?logo=openjdk&logoColor=white)](pom.xml)
[![Karate](https://img.shields.io/badge/Karate-2.1.2-2EAD33?logoColor=white)](pom.xml)
[![Testcontainers](https://img.shields.io/badge/Testcontainers-Postgres%20%2B%20PostgREST-2496ED?logo=docker&logoColor=white)](src/test/java/dev/diegonava/karate/ApiUnderTest.java)

API suite in **Karate 2 · Java 21**, running against an API it starts itself.

```bash
./mvnw test
```

That is the whole setup. No API key, no account, no hosted service, no `.env`, and no Maven
install — the wrapper fetches it. Docker and a JDK.

---

## Why Karate, and not the REST Assured suite again

I already have [an API suite in REST Assured](https://github.com/Diegonava150/restassured-automation).
Writing the same thing twice in a different DSL would prove nothing, so this repository is built
around the two things Karate does that the other one cannot, and its
[*Deliberately not covered*](https://github.com/Diegonava150/restassured-automation#deliberately-not-covered)
section names one of them outright:

> **Consumer-driven contract testing.** … That is provider-side self-consistency, and it is a
> different claim from a Pact-style contract: no real consumer's expectations are recorded
> anywhere, so nothing would notice a change that is internally consistent and still breaks a
> caller.

**1. A mock that is held to the same contract as the real service.** In Karate a mock *is* a
feature file, so the stand-in and the tests are the same language and reviewable by the same
people. [`contract.feature`](src/test/resources/features/contract.feature) runs one set of
consumer expectations twice — against the real containerised service, and against the mock — and
requires both to pass.

**2. Deeply nested responses, asserted as one shape.** PostgREST reads the foreign keys and lets a
caller embed related rows, so one request returns an author with their books and each book with
its reviews. Karate compares that whole document against a single expected shape and names the
exact path that differs. In an imperative client the same assertion is a dozen path lookups and a
dozen chances to check the wrong index.

---

## The contract, and why it is not decoration

A mock that is only ever checked against itself is a fixture with opinions. It agrees with
whatever it was written to agree with, forever; it drifts the moment the provider changes, keeps
passing, and the first thing to notice is production.

So the mock is never checked against itself. [`catalog-consumer.feature`](src/test/resources/contracts/catalog-consumer.feature)
records only what a caller actually depends on — shapes, not values, and deliberately not
everything the API can do, because a contract that restates the whole implementation pins the
provider in place and stops being a contract. It is then run against both.

**That comparison is itself verified.** CI has a second job that removes one field from the mock
and requires the suite to go red — and to go red *for that reason*, in the right scenario, with
the real service still passing. A green result there would mean the contract check had quietly
stopped checking, which is worse than not having it: the report would still show two passing
scenarios.

Reproduced locally before it was written into CI:

```
- the mock satisfies the same consumer contract
  $[1] | actual does not contain key - 'inPrint' (MAP:MAP)
```

The real-service scenario passed in the same run. That difference is the whole point.

---

## What the suite covers

**24 scenarios across 3 features**, run four at a time.

| Feature | What it pins down |
| --- | --- |
| [`books.feature`](src/test/resources/features/books.feature) | CRUD, and every happy path has a negative counterpart. The negatives assert on **SQLSTATE codes** — `23502`, `23505`, `23514`, `23503` — not on a bare 400. "Something was wrong" does not survive a refactor of how errors are surfaced; "a CHECK constraint rejected this" does. |
| [`embedding.feature`](src/test/resources/features/embedding.feature) | Nested resources assembled across three joined tables, `!inner` filtering that narrows the *parent*, and the difference between an empty embedded list and a missing one. |
| [`contract.feature`](src/test/resources/features/contract.feature) | The mock and the real service answering the same consumer. |

Those error codes are real. They come from Postgres rejecting the write, which is the entire
reason the suite starts its own database rather than pointing at something that returns numbers
it was told to return.

### Written for concurrency, not around it

The first run failed with `actual array length is 5` and a stray book titled `Temporary` — a
scenario two hundred lines away had created it while the list assertion was counting. The fix was
not to serialise the suite. An exact count asserts that nothing else is happening, which is false
by construction when four scenarios run at once, so the assertions now say what is actually being
claimed: the seeded catalogue is present and every row is well formed.

---

## How it is wired

```
src/test/java/dev/diegonava/karate/
  ApiUnderTest.java      the containers, started once on first touch
  KarateSuiteTest.java   the only entry point: start, hand over addresses, run in parallel
src/test/resources/
  db/init.sql            the schema, constraints and seed — i.e. the API itself
  features/              swept by the runner
  contracts/             NOT swept: the mock, and the consumer contract
  karate-config.js       reads the runtime addresses back
```

**There is no base URL anywhere in this repository.** Docker assigns an ephemeral host port on
every run, so the address is only knowable at runtime. The runner starts the containers, passes
the resolved address in as a system property, and `karate-config.js` reads it back. A hardcoded
URL would be wrong by construction, and two runs on one machine would collide on a fixed one.

**`contracts/` is a directory, not a tag.** The mock and the consumer contract must never be
executed as ordinary tests: a mock feature run without a request in flight fails on
`request is not defined`, and the consumer contract has no `target` unless a caller supplies one.
Tagging them `@ignore` and filtering `~@ignore` on the runner was tried first and did not hold.
A directory the runner is never pointed at does not depend on tag-inheritance rules.

**Singleton containers, not `@Testcontainers`.** The JUnit extension ties container lifecycle to a
test class, and Karate's scenarios are not JUnit classes — there is no per-class boundary to hang
a container on. Testcontainers documents the singleton pattern for exactly this case.

---

## Deliberately not covered

- **Performance.** [`karate-gatling`](https://github.com/karatelabs/karate/tree/master/karate-gatling)
  can reuse these same feature files as load scenarios, which is a genuinely good reason to pick
  Karate. It is not here yet, and a load number measured against a container on a laptop would
  describe Docker rather than the API.
- **Authentication.** PostgREST supports JWT roles; this suite runs everything as one anonymous
  role. Adding auth would test PostgREST's implementation rather than this suite's ability to
  handle it.
- **A published report.** The Karate HTML report is uploaded as a CI artifact but not published
  to Pages. That is a deliberate first-push boundary, not an oversight.
- **Automated bumping of the two container images.** The Postgres and PostgREST tags are Java
  string constants, which Dependabot's docker updater cannot read — it parses Dockerfiles and
  compose files, and this repository has neither. Those two pins are bumped by hand.

---

## Notes for whoever edits the Karate next

Three things this project was written wrong against first, each of which produced an error
message that pointed somewhere else:

- **`* def x = ...` consumes one line.** A ternary broken across three lines assigns only the
  first, which produced a boolean `response` and the opaque
  `unsupported response body type: true`.
- **The JS engine has no `String.contains`.** It is `includes`, or `indexOf(..) >= 0`.
- **`param 'name.with.dots' = ...` sends the quotes.** PostgREST then filters on a column called
  `'books` and answers 400. Use the `params { ... }` map form. Every sane URL encoding of that
  query returns 200 against the running service, so the encoding was never the problem.

And one Maven one: `target/test-classes` keeps resources that have been deleted from the source
tree. After moving a feature file, `./mvnw clean test` — otherwise the runner executes both
copies and the failure describes a file that no longer exists where it says it does.
