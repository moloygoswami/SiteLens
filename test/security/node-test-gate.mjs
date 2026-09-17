/**
 * Security gate — `node:test` half.
 *
 * Runs the Firestore/Storage rules suite authored with `node:test` and fails
 * the gate when the suite does not execute the expected number of tests.
 * This guards against a silent pass: `node --test` exits 0 when a file
 * declares no tests at all.
 *
 * Requires the Firebase emulator (firestore :8080 / storage :9199) to be
 * running, e.g. `firebase emulators:exec --only firestore,storage "npm test"`.
 */
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const MIN_PASSED = 57;
const suite = fileURLToPath(new URL('./firestore_rules.test.js', import.meta.url));

const result = spawnSync(
  process.execPath,
  ['--test', '--test-reporter=spec', suite],
  { encoding: 'utf8' },
);

const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
process.stdout.write(output);

const readMetric = (label) => {
  const match = output.match(new RegExp(`^\\u2139 ${label} (\\d+)$`, 'm'));
  return match ? Number(match[1]) : NaN;
};

const passed = readMetric('pass');
const failed = readMetric('fail');
const skipped = readMetric('skipped');

const ok =
  result.status === 0 &&
  failed === 0 &&
  skipped === 0 &&
  Number.isFinite(passed) &&
  passed >= MIN_PASSED;

if (!ok) {
  console.error(
    `\n[node:test gate] FAILED — exit=${result.status} passed=${passed} failed=${failed} skipped=${skipped} ` +
      `(expected >= ${MIN_PASSED} passed, 0 failed, 0 skipped)`,
  );
  process.exit(1);
}

console.log(
  `\n[node:test gate] OK — ${passed} passed, ${failed} failed, ${skipped} skipped`,
);
