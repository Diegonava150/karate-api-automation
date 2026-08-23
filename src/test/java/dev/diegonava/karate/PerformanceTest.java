package dev.diegonava.karate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.karatelabs.core.Runner;
import io.karatelabs.core.SuiteResult;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * The performance suite, which needs a database worth measuring.
 *
 * <p>Excluded from {@code mvn test} and run on its own, because it needs a fixture the functional
 * suite must not have. It is invoked with both properties set:
 *
 * <pre>
 *   ./mvnw test -Dtest=PerformanceTest -Dapi.extraData=db/volume.sql -DfailIfNoSpecifiedTests=false
 * </pre>
 *
 * <p>{@code api.extraData} layers ten thousand books and fifty thousand reviews on top of the
 * ordinary schema. Without it every scenario under {@code performance/} asserts the opposite of
 * the truth: Postgres declines to use an index on a four-row table, correctly, so a plan taken
 * against the eleven-row seed shows sequential scans that are the right answer at that size and
 * the wrong answer at any size anyone would run.
 *
 * <p>Nothing here asserts a wall-clock number. The two techniques that survive a shared CI runner
 * are query plans, which contain no timing at all, and ratios measured within a single run, where
 * the machine's speed divides out. An absolute threshold is either loose enough never to fire or
 * tight enough to fire at random — this repository has already withdrawn one performance claim
 * for exactly that reason.
 */
class PerformanceTest {

    private static final Logger log = LoggerFactory.getLogger(PerformanceTest.class);

    @Test
    @DisplayName("query plans and scaling behaviour, against a database with volume in it")
    void runPerformanceSuite() {
        // Fail with a sentence rather than with five confusing assertion errors. Running this
        // against the small seed is the single most likely mistake, and its symptom — plans full
        // of legitimate sequential scans — looks like a genuine finding.
        String extraData = System.getProperty("api.extraData");
        assertEquals(
                "db/volume.sql",
                extraData,
                "the performance suite needs -Dapi.extraData=db/volume.sql; against the ordinary "
                        + "eleven-row seed every plan assertion here is meaningless");

        String baseUrl = ApiUnderTest.baseUrl();
        log.info("Performance suite against {}", baseUrl);

        SuiteResult results = Runner.path("classpath:performance")
                .systemProperty("api.baseUrl", baseUrl)
                .outputHtmlReport(true)
                // Serial. These scenarios time each other's queries, and four threads competing
                // for one small container would put the contention into the measurement.
                .parallel(1);

        assertTrue(
                results.getScenarioCount() >= 5,
                "expected the performance suite, but only " + results.getScenarioCount()
                        + " scenario(s) ran");

        assertEquals(
                0,
                results.getScenarioFailedCount(),
                () -> String.join(System.lineSeparator(), results.getErrors()));
    }
}
