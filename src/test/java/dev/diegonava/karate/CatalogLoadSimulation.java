package dev.diegonava.karate;

import static io.gatling.javaapi.core.CoreDsl.global;
import static io.gatling.javaapi.core.CoreDsl.rampUsers;
import static io.gatling.javaapi.core.CoreDsl.scenario;
import static io.karatelabs.gatling.KarateDsl.karateFeature;
import static io.karatelabs.gatling.KarateDsl.karateProtocol;

import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;
import io.karatelabs.gatling.KarateProtocolBuilder;

/**
 * A load profile built from the functional suite, not from a second description of it.
 *
 * <p>This is the reason the README claims Karate earns its place twice. The scenarios driven here
 * are the same {@code .feature} files the correctness suite runs — selected by the {@code @perf}
 * tag, not copied — so a load test cannot quietly drift from the behaviour it is supposed to be
 * measuring. In most stacks the load script is a parallel implementation of the API client that
 * rots on its own schedule.
 *
 * <p>Deliberately not part of {@code mvn test}. It is run on demand:
 *
 * <pre>
 *   ./mvnw gatling:test -Dgatling.simulationClass=dev.diegonava.karate.CatalogLoadSimulation
 * </pre>
 *
 * <h2>What this number is, and what it is not</h2>
 *
 * <p>It is a regression signal against a fixed, self-contained stack: same containers, same seed
 * data, same machine. Run it before and after a change and a difference means something.
 *
 * <p>It is <em>not</em> a capacity figure for PostgREST or for anything else. The database, the
 * API and the load generator are all sharing one laptop or one CI runner, so the number describes
 * that arrangement. Publishing it as throughput would be measuring Docker and calling it the API
 * — which is why the README lists performance under what this repository does not claim, even
 * now that the simulation exists.
 */
public class CatalogLoadSimulation extends Simulation {

    /**
     * Gatling runs the simulation in its own JVM, so the containers have to be started here as
     * well — {@code KarateSuiteTest} is not involved. {@code ApiUnderTest} is a singleton, so this
     * is the same code path the functional suite uses, and {@code karate-config.js} reads the
     * address back out of the system property exactly as it does there.
     */
    static {
        System.setProperty("api.baseUrl", ApiUnderTest.baseUrl());
    }

    private final KarateProtocolBuilder protocol = karateProtocol();

    /**
     * Read-only scenarios only.
     *
     * <p>{@code @perf} is applied by hand rather than pointing this at whole feature files,
     * because the suite creates and deletes books. Replaying a write under load grows the table
     * beneath the very queries being timed, so the run would measure its own side effects and the
     * numbers would drift upward for a reason that has nothing to do with the code.
     */
    private final ScenarioBuilder readCatalog = scenario("catalog reads")
            .exec(karateFeature("classpath:features/books.feature", "@perf"))
            .exec(karateFeature("classpath:features/embedding.feature", "@perf"))
            .exec(karateFeature("classpath:features/reviews.feature", "@perf"));

    {
        // Small and short on purpose. The point is a repeatable comparison, not a stress test —
        // and a profile that saturates a shared CI runner produces a number about the runner.
        int users = Integer.getInteger("perf.users", 5);
        int rampSeconds = Integer.getInteger("perf.ramp.seconds", 10);

        setUp(readCatalog.injectOpen(rampUsers(users).during(java.time.Duration.ofSeconds(rampSeconds))))
                .protocols(protocol)
                // The only absolute assertion here, and the only one that means the same thing on
                // every machine. Zero failed requests under concurrency is a property of the code;
                // a latency threshold is a property of whichever runner GitHub handed out, which
                // is why there is not one.
                //
                // It is not a formality either: connection-pool exhaustion, a transaction deadlock
                // and a 5xx under contention all land here, and none of them shows up in a
                // single-user functional run.
                .assertions(global().failedRequests().count().is(0L));
    }
}
