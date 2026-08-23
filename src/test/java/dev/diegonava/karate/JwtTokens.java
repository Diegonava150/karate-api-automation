package dev.diegonava.karate;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Mints the HS256 tokens PostgREST authenticates with.
 *
 * <p>PostgREST reads a {@code role} claim and switches the database session to that role, so a
 * token is not a bearer of permissions in itself — it names a Postgres role, and the grants in
 * {@code init.sql} decide what that role may do. Authorisation lives in the schema, which is the
 * whole point of the arrangement and the reason these tests can assert on it.
 *
 * <p>Hand-rolled rather than pulled from a JWT library. Signing HS256 is a hash and two base64url
 * encodings, and the alternative is a dependency whose only job in this repository would be to
 * produce four short strings. It also keeps the failure modes visible: an expired token and a
 * token signed with the wrong key are both one line away, and both are things the suite asserts
 * on.
 */
public final class JwtTokens {

    /**
     * The signing key, shared with the container.
     *
     * <p>Not a secret in any meaningful sense — it is generated for a database that exists for
     * the length of one test run on an ephemeral port, and it is committed on purpose so the
     * suite stays reproducible. PostgREST rejects secrets shorter than 32 characters outright.
     */
    static final String SECRET = "karate-api-automation-test-signing-key-not-a-secret";

    private static final Base64.Encoder URL64 = Base64.getUrlEncoder().withoutPadding();

    private JwtTokens() {}

    /** A token naming {@code role}, valid for an hour. */
    public static String forRole(String role) {
        return sign(role, Instant.now().plusSeconds(3600), SECRET);
    }

    /** A token that was valid and is not any more, for the scenario that asserts expiry. */
    public static String expiredForRole(String role) {
        return sign(role, Instant.now().minusSeconds(60), SECRET);
    }

    /**
     * A well-formed token signed with the wrong key.
     *
     * <p>The distinction from a garbled string matters: this one parses, carries a plausible
     * role, and is refused purely because the signature does not verify. A test that only sends
     * "not-a-token" proves the parser rejects nonsense, not that the signature is checked.
     */
    public static String forgedForRole(String role) {
        return sign(role, Instant.now().plusSeconds(3600), "an-entirely-different-signing-key-32ch");
    }

    private static String sign(String role, Instant expiry, String key) {
        String header = URL64.encodeToString("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));
        String payload = URL64.encodeToString(
                "{\"role\":\"%s\",\"exp\":%d}".formatted(role, expiry.getEpochSecond())
                        .getBytes(StandardCharsets.UTF_8));
        String signingInput = header + "." + payload;

        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            String signature = URL64.encodeToString(mac.doFinal(signingInput.getBytes(StandardCharsets.UTF_8)));
            return signingInput + "." + signature;
        } catch (Exception e) {
            throw new IllegalStateException("Could not sign a test JWT", e);
        }
    }
}
