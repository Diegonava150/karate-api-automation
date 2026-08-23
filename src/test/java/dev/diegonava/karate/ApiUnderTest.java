package dev.diegonava.karate;

import java.time.Duration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.Network;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.utility.MountableFile;

/**
 * The API the suite tests, started by the suite.
 *
 * <p>Postgres holds the data and PostgREST turns the schema into an HTTP API, so
 * {@code src/test/resources/db/init.sql} is simultaneously the fixture and the service
 * definition. The whole setup is {@code ./mvnw test} plus a Docker daemon: no API key, no
 * account, no hosted sandbox, and no shared state that another run can move underneath this
 * one.
 *
 * <p>That last point is not theoretical. The sibling REST Assured project was written against
 * a free hosted mock, which filled to its hundred-row cap and then failed every request with
 * {@code Max number of elements reached} — a suite that could not be made green from inside
 * its own repository. Owning the dependency is the fix.
 *
 * <h2>Why a singleton rather than {@code @Testcontainers}</h2>
 *
 * <p>The JUnit extension ties container lifecycle to a test class. Karate's scenarios are not
 * JUnit classes — they are driven by one runner — so there is no per-class boundary for the
 * extension to hang a container on. Testcontainers documents the singleton pattern for exactly
 * this case: started once on first touch, reaped by Ryuk at JVM exit.
 */
public final class ApiUnderTest {

    private static final Logger log = LoggerFactory.getLogger(ApiUnderTest.class);

    private static final String POSTGRES_IMAGE = "postgres:16-alpine";
    private static final String POSTGREST_IMAGE = "postgrest/postgrest:v12.2.12";

    private static final String DB_NAME = "catalog";
    private static final String DB_USER = "postgres";
    private static final String DB_PASSWORD = "postgres";

    /** Must match the role created at the bottom of init.sql. */
    private static final String POSTGREST_ROLE = "authenticator";

    private static final String POSTGREST_PASSWORD = "postgrest_pw";
    private static final String ANON_ROLE = "web_anon";
    private static final String SCHEMA = "api";
    private static final int POSTGREST_PORT = 3000;

    /** A private network so PostgREST can reach Postgres by alias rather than by mapped port. */
    private static final Network NETWORK = Network.newNetwork();

    private static final PostgreSQLContainer<?> POSTGRES = postgres();

    private static PostgreSQLContainer<?> postgres() {
        PostgreSQLContainer<?> container = new PostgreSQLContainer<>(DockerImageName.parse(POSTGRES_IMAGE))
                .withDatabaseName(DB_NAME)
                .withUsername(DB_USER)
                .withPassword(DB_PASSWORD)
                .withNetwork(NETWORK)
                .withNetworkAliases("db")
                .withCopyFileToContainer(
                        MountableFile.forClasspathResource(schemaResource()),
                        "/docker-entrypoint-initdb.d/01-schema.sql");

        // Postgres runs everything in that directory in alphabetical order, which is what lets a
        // data-only file be layered on the real schema instead of forking a third copy of it.
        // Used by the performance suite, where eleven rows would make every plan meaningless.
        extraDataResource()
                .ifPresent(resource -> container.withCopyFileToContainer(
                        MountableFile.forClasspathResource(resource),
                        "/docker-entrypoint-initdb.d/02-data.sql"));

        return container;
    }

    private static final GenericContainer<?> POSTGREST =
            new GenericContainer<>(DockerImageName.parse(POSTGREST_IMAGE))
                    .withNetwork(NETWORK)
                    .withExposedPorts(POSTGREST_PORT)
                    .withEnv(
                            "PGRST_DB_URI",
                            "postgres://%s:%s@db:5432/%s"
                                    .formatted(POSTGREST_ROLE, POSTGREST_PASSWORD, DB_NAME))
                    .withEnv("PGRST_DB_SCHEMA", SCHEMA)
                    .withEnv("PGRST_DB_ANON_ROLE", ANON_ROLE)
                    // Without this every bearer token is rejected and the failure looks like a
                    // permissions bug rather than a missing configuration value. PostgREST
                    // refuses secrets shorter than 32 characters outright.
                    .withEnv("PGRST_JWT_SECRET", JwtTokens.SECRET)
                    // Lets a caller ask for the query plan instead of the rows, via
                    // `Accept: application/vnd.pgrst.plan`. That is how the performance suite
                    // asserts on index usage without timing anything, which is the only kind of
                    // performance assertion a shared CI runner cannot make flaky.
                    //
                    // On in this container because it is a fixture that lives for one test run.
                    // It exposes the shape of the schema to anyone who can reach the API, so it
                    // would not be on in production.
                    .withEnv("PGRST_DB_PLAN_ENABLED", "true")
                    // Without this PostgREST caches the schema at boot and never notices the
                    // tables, answering 404 for every endpoint that plainly exists.
                    .withEnv("PGRST_DB_CONFIG", "false")
                    .waitingFor(
                            Wait.forHttp("/books?limit=1")
                                    .forPort(POSTGREST_PORT)
                                    .forStatusCode(200)
                                    .withStartupTimeout(Duration.ofMinutes(2)));

    private static boolean started;

    private ApiUnderTest() {}

    /**
     * Which schema to boot against.
     *
     * <p>Overridable so CI can point the same suite at a deliberately weakened copy and require
     * it to go red — a negative test nobody has watched fail proves nothing.
     */
    private static String schemaResource() {
        return System.getProperty("api.schema", "db/init.sql");
    }

    /**
     * An optional second SQL file, applied after the schema.
     *
     * <p>Absent for every functional run. The performance suite sets it to {@code db/volume.sql},
     * which adds ten thousand books and fifty thousand reviews — the point at which a query plan
     * starts describing a database someone might actually operate.
     */
    private static java.util.Optional<String> extraDataResource() {
        return java.util.Optional.ofNullable(System.getProperty("api.extraData"));
    }

    /** Base URI of the running API. Starts the stack on first call. */
    public static synchronized String baseUrl() {
        if (!started) {
            log.info("Starting {} and {}", POSTGRES_IMAGE, POSTGREST_IMAGE);
            POSTGRES.start();
            POSTGREST.start();
            started = true;
            log.info("API under test is up at {}", url());
        }
        return url();
    }

    private static String url() {
        return "http://%s:%d".formatted(POSTGREST.getHost(), POSTGREST.getMappedPort(POSTGREST_PORT));
    }

    public static String postgresImage() {
        return POSTGRES_IMAGE;
    }

    public static String postgrestImage() {
        return POSTGREST_IMAGE;
    }
}
