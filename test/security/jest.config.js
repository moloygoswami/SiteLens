/**
 * Jest gate for the SiteLens Firestore/Storage security suites.
 *
 * `firestore_rules.test.js` is authored with `node:test` and is executed
 * separately by `npm run test:rules` (see node-test-gate.mjs). Running it under
 * Jest registers zero Jest tests and fails the suite with
 * "Your test suite must contain at least one test", so it is excluded here.
 *
 * Jest still fails the run when a matched suite reports zero tests, so an
 * empty/misconfigured suite cannot silently pass.
 */
module.exports = {
  testEnvironment: 'node',
  testPathIgnorePatterns: ['/node_modules/', 'firestore_rules\\.test\\.js$'],
};
