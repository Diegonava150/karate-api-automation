package dev.diegonava.karate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.intuit.karate.Results;
import com.intuit.karate.Runner;
import com.intuit.karate.core.MockServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * The whole suite, in one JVM.
 *
 * <p>Karate scenarios are not JUnit classes, so there is exactly one entry point: start what the
 * scenarios need, hand the addresses over as system properties, and run the features in
 * parallel. {@code karate-config.js} reads those properties back.
 *
 * <p>No base URL is committed anywhere in this repository. Docker assigns an ephemeral host port
 * on every run, so the address is only knowable once the container is up — a hardcoded URL would
 * be wrong by construction, and two runs on one machine would collide on a fixed one.
 */
class KarateSuiteTest {

    private static final Logger log = LoggerFactory.getLogger(KarateSuiteTest.class);

    private static MockServer mock;

    @Test
    @DisplayName("every feature passes against the API the suite starts itself")
    void runAll() {
        String baseUrl = ApiUnderTest.baseUrl();

        // Port 0 asks the OS for a free one. A fixed port is the classic way to make a suite
        // that passes alone and fails on a machine already running something.
        mock = MockServer.feature("classpath:contracts/catalog-mock.feature").port(0).build();
        String mockUrl = "http://localhost:" + mock.getPort();
        log.info("API under test: {}   contract mock: {}", baseUrl, mockUrl);

        int threads = Integer.getInteger("karate.threads", 4);

        // Only `features/` is swept. The mock and the consumer contract live under
        // `contracts/` precisely so this cannot reach them: a mock feature executed as a test
        // runs its scenarios with no request in flight, and fails on `request is not defined`
        // for reasons that look like a Karate version problem and are not. Tagging them was
        // tried first and did not hold; a directory the runner is never pointed at does.
        Results results = Runner.path("classpath:features")
                .systemProperty("api.baseUrl", baseUrl)
                .systemProperty("mock.baseUrl", mockUrl)
                .outputHtmlReport(true)
                // Consumed by CI to publish a report, and by anyone who wants the results in a
                // format other than Karate's own HTML.
                .outputCucumberJson(true)
                .parallel(threads);

        log.info("Karate report: {}", results.getReportDir());

        // A suite that runs nothing passes. That is the failure mode worth guarding, because it
        // is indistinguishable from success in every summary line: a mis-typed classpath, a
        // feature directory left out of <testResources>, a tag filter matching nothing. The
        // floor is deliberately a real number rather than 1.
        assertTrue(
                results.getScenarioCount() >= 20,
                "expected the full suite, but only " + results.getScenarioCount()
                        + " scenario(s) ran — features are probably not on the classpath");

        assertEquals(0, results.getFailCount(), results.getErrorMessages());
    }

    @AfterAll
    static void stopMock() {
        if (mock != null) {
            mock.stop();
        }
    }
}
