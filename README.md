# Karate API automation — hermetic, with a contract the mock cannot fake

[![CI](https://github.com/Diegonava150/karate-api-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/Diegonava150/karate-api-automation/actions/workflows/ci.yml)
[![Java 21](https://img.shields.io/badge/Java-21-007396?logo=openjdk&logoColor=white)](pom.xml)
[![Karate](https://img.shields.io/badge/Karate-2.1.2-2EAD33?logoColor=white)](pom.xml)
[![Testcontainers](https://img.shields.io/badge/Testcontainers-Postgres%20%2B%20PostgREST-2496ED?logo=docker&logoColor=white)](src/test/java/dev/diegonava/karate/ApiUnderTest.java)

**📊 [Live Karate report](https://diegonava150.github.io/karate-api-automation/)** — published from
every push to `main`, pass or fail. A report you only get when everything was green is a report you
never need.

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

**50 scenarios across 5 features**, run four at a time.

| Feature | What it pins down |
| --- | --- |
| [`authors.feature`](src/test/resources/features/authors.feature) | `UNIQUE(email)` on create *and* update, the deliberately weak `email LIKE '%@%.%'` check, non-blank names, and a two-hop cascade — deleting an author takes their books and the reviews of those books. The second hop is the one worth asserting: a schema that cascades one level and orphans the next looks correct from the parent. |
| [`books.feature`](src/test/resources/features/books.feature) | CRUD, and every happy path has a negative counterpart. The negatives assert on **SQLSTATE codes** — `23502`, `23505`, `23514`, `23503` — not on a bare 400. "Something was wrong" does not survive a refactor of how errors are surfaced; "a CHECK constraint rejected this" does. |
| [`reviews.feature`](src/test/resources/features/reviews.feature) | `rating BETWEEN 1 AND 5`, at both boundaries and on **UPDATE as well as INSERT** — a constraint enforced only on the way in is a real and common bug that a passing create scenario says nothing about. |
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

## Proving the negative tests can fail

Seventeen scenarios assert that the API *rejects* something. All of them are green, and a green
tick says nothing about whether the assertion held or simply never ran.

So CI runs the whole suite a second time against
[`init-weakened.sql`](src/test/resources/db/init-weakened.sql), a copy of the schema with the
constraints those scenarios assert on removed. Each entry in
[`mutation-expectations.txt`](src/test/resources/db/mutation-expectations.txt) must go red, by
name — not merely "the suite failed", which one surviving failure would satisfy while every other
mutation quietly stopped being caught.

The most interesting entry in that file is not a negative scenario at all. With the unique index
removed, the provider answers `201` where the consumer contract requires `409`, so **the contract
fails against the real service** while the mock keeps passing. That is the same machinery that
catches mock drift, running in the other direction — and the diff between the two runs points
straight at the provider.

**The ledger cannot go stale unnoticed.** A separate check —
[`check_mutation_ledger.py`](scripts/check_mutation_ledger.py), runnable locally — cross-references
every `@negative` scenario against the ledger and fails the build if one is unaccounted for, or if
the ledger names a scenario that no longer exists. Add a negative test and forget the ledger, and
the mutation job would otherwise keep passing on the entries it still knows about: nothing red,
and the coverage number quietly a lie.

That check is the entire reason the tag exists. Before it, four of this repository's five tag
families — `@smoke`, `@catalog`, `@contract`, `@negative` — selected nothing at all. Decoration
that looked like configuration, so three were deleted and the fourth was given a job.

Two scenarios are documented as *not* provable this way rather than counted. Both assert `23503`,
and both are backed by foreign keys that PostgREST also uses to derive its embeddable
relationships: dropping them would prove the assertions can fail and simultaneously break every
scenario in `embedding.feature` for an unrelated reason. A mutation whose blast radius is the
whole suite says nothing about the one assertion it was aimed at.

---

## Load, from the same feature files

```bash
./mvnw test-compile gatling:test -Dgatling.simulationClass=dev.diegonava.karate.CatalogLoadSimulation
```

[`CatalogLoadSimulation`](src/test/java/dev/diegonava/karate/CatalogLoadSimulation.java) drives the
scenarios tagged `@perf` — **the same `.feature` files the correctness suite runs**, selected by
tag rather than copied. In most stacks the load script is a parallel implementation of the API
client that rots on its own schedule; here it cannot drift from the behaviour it is measuring,
because it is the same text.

`karate-gatling` brings Gatling's *Java* DSL, so the simulation is a plain Java class: no Scala
source set, no second language to keep in step. Only read-only scenarios are tagged — replaying a
write under load grows the table beneath the queries being timed, so the run would measure its own
side effects.

Last local run: **30 requests, 0 failed, mean 4 ms, p95 6 ms.**

That number is a regression signal against a fixed stack — same containers, same seed, same
machine — and nothing else. The database, the API and the load generator all share one host, so
publishing it as throughput would be measuring Docker and calling it the API.

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

- **Performance as a *number*.** The Gatling profile above is a regression signal, not a capacity
  figure, and CI runs it only on demand. A load profile in the per-push build turns every commit
  into a timing measurement of whichever runner GitHub handed out.
- **Authentication.** PostgREST supports JWT roles; this suite runs everything as one anonymous
  role. Adding auth would test PostgREST's implementation rather than this suite's ability to
  handle it.
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
