/*
 * Karate reads this once per scenario and the returned object becomes the variables every
 * feature can see.
 *
 * There is no base URL committed anywhere in this repository, and that is deliberate. Docker
 * assigns an ephemeral host port on every run, so the address is only knowable at runtime — a
 * hardcoded URL would be wrong by construction, and two runs on one machine would collide on a
 * fixed one. The runner starts the containers and passes the resolved address in as a system
 * property; this reads it back.
 */
function fn() {
  var env = karate.env || 'container';

  var baseUrl = karate.properties['api.baseUrl'];
  if (!baseUrl) {
    // Failing loudly here beats a suite full of connection errors to `nullundefined`, which
    // is what an unset base URL actually looks like from inside a scenario.
    throw new Error(
      'api.baseUrl was not set. Run the suite through KarateSuiteTest (or ContractTest), ' +
        'which starts the containers and passes the resolved address in.'
    );
  }

  // Only the contract feature needs this, and only when the runner has started a mock, so an
  // absent value is not an error here — the feature that uses it will fail plainly if it is
  // missing, which is a better message than one thrown from config for every scenario.
  var mockUrl = karate.properties['mock.baseUrl'] || null;

  var config = {
    env: env,
    baseUrl: baseUrl,
    mockUrl: mockUrl,

    // Asking PostgREST to hand back the row it just wrote turns a 201-with-empty-body into a
    // 201 carrying the created resource, so a create can be asserted on in one step instead of
    // a create followed by a read.
    returnRepresentation: { Prefer: 'return=representation' }
  };

  // Fail fast rather than let every scenario time out separately.
  karate.configure('connectTimeout', 10000);
  karate.configure('readTimeout', 20000);

  return config;
}
