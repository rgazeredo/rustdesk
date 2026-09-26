// Autonomous renewal test for Android client
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, cpSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';

const deps = process.env.BC_TEST_DEPS;
if (!deps) throw new Error('BC_TEST_DEPS directory required');

const work = mkdtempSync(join(tmpdir(), 'azsign-renewal-test-'));
const classes = join(work, 'classes');
mkdirSync(classes);
const classpath = `${resolve(deps)}/*:${classes}`;

// Compile Java sources
execFileSync('javac', [
  '-cp', `${resolve(deps)}/*`,
  '-d', classes,
  join(import.meta.dirname, 'AzsignAccessIdentity.java'),
  join(import.meta.dirname, 'AzsignRenewalScheduler.java'),
  join(import.meta.dirname, 'AzsignRenewalHttp.java'),
  join(import.meta.dirname, 'AzsignRenewalRuntime.java'),
  join(import.meta.dirname, 'RenewalHttpTest.java'),
  join(import.meta.dirname, 'RenewalRuntimeTest.java'),
  join(import.meta.dirname, 'RenewalTest.java')
]);

const id = '0199a000-0000-7000-8000-000000000001';
const dir = join(work, 'device');
mkdirSync(dir);

const openssl = (...args) => execFileSync('openssl', args, { cwd: work, stdio: ['ignore', 'pipe', 'pipe'] });
const java = (...args) => execFileSync('java', ['-cp', classpath, 'RenewalTest', ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

// 1. Generate Disposable CA
openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'ca.key', '-out', 'ca.pem', '-days', '2', '-subj', '/CN=Disposable test CA', '-addext', 'basicConstraints=critical,CA:TRUE');

// 2. Prepare identity locally (generates key.der and CSR)
const identityClasses = join(work, 'classes');
execFileSync('javac', ['-cp', `${resolve(deps)}/*:${classes}`, '-d', identityClasses, join(import.meta.dirname, 'IdentityTest.java')]);
const csrBase64 = execFileSync('java', ['-cp', classpath, 'IdentityTest', 'prepare', dir, id], { encoding: 'utf8' });
writeFileSync(join(work, 'request.der'), Buffer.from(csrBase64, 'base64'));
openssl('req', '-inform', 'DER', '-in', 'request.der', '-out', 'request.pem');

// 3. Issue initial leaf cert (valid for 1 day)
writeFileSync(join(work, 'client.ext'), 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=clientAuth\n');
openssl('x509', '-req', '-in', 'request.pem', '-CA', 'ca.pem', '-CAkey', 'ca.key', '-set_serial', '1', '-days', '1', '-extfile', 'client.ext', '-out', 'initial_client.pem');
openssl('x509', '-in', 'initial_client.pem', '-outform', 'DER', '-out', 'initial_client.der');
openssl('x509', '-in', 'ca.pem', '-outform', 'DER', '-out', 'ca.der');

const initialLeafDer = readFileSync(join(work, 'initial_client.der'));
const caDer = readFileSync(join(work, 'ca.der'));

// Write initial active.json
const activeJson = {
  renewal_origin: 'https://app.azsign.com.br',
  identity_id: id,
  profile: {
    host: 'rustdesk.azsign.com.br',
    server_name: 'rustdesk.azsign.com.br',
    registration: 32116,
    rendezvous: 32117,
    relay: 32118
  },
  certificate_base64: initialLeafDer.toString('base64'),
  ca_base64: caDer.toString('base64'),
  expires_at: Date.now() + 86400000
};
writeFileSync(join(dir, 'active.json'), JSON.stringify(activeJson));
assert.equal(execFileSync('java', ['-cp', classpath, 'com.carriez.flutter_hbb.RenewalHttpTest', dir, id], {encoding: 'utf8'}).trim(), 'http-verified');
console.log('✓ Real HTTP adapter: request shape, timeout, redirect refusal, bounded JSON, error classification and cancellation');
const runtimeFiles = join(work, 'runtime-files');
mkdirSync(runtimeFiles);
cpSync(dir, join(runtimeFiles, 'azsign-access-poc'), {recursive: true});
assert.equal(execFileSync('java', ['-cp', classpath, 'RenewalRuntimeTest', runtimeFiles], {encoding: 'utf8'}).trim(), 'runtime-verified');
console.log('✓ Application runtime resumes enrollment from disk and prevents duplicate schedulers across restart');

// 4. Issue renewed leaf cert (serial 2)
openssl('x509', '-req', '-in', 'request.pem', '-CA', 'ca.pem', '-CAkey', 'ca.key', '-set_serial', '2', '-days', '2', '-extfile', 'client.ext', '-out', 'renewed_client.pem');
openssl('x509', '-in', 'renewed_client.pem', '-outform', 'DER', '-out', 'renewed_client.der');

// Test 1: Successful autonomous renewal with key retention and atomic persistence
assert.equal(java('test-cancel', dir, id, join(work, 'renewed_client.der'), join(work, 'ca.der')).trim(), 'cancel-verified');
console.log('✓ Cancellation does not wait for the network and a late response cannot overwrite enrollment');
const res1 = java('test-success', dir, id, join(work, 'renewed_client.der'), join(work, 'ca.der'));
assert.equal(res1.trim(), 'success-verified');
console.log('✓ Autonomous renewal succeeded: key retained, active.json atomically updated, transport authorized');

assert.equal(java('test-idempotent', dir, id, join(work, 'renewed_client.der'), join(work, 'ca.der')).trim(), 'idempotent-verified');
assert.equal(java('test-replay', dir, id, join(work, 'initial_client.der'), join(work, 'ca.der')).trim(), 'rejected-verified');
for (const scenario of ['test-profile-change', 'test-ca-change']) {
  assert.equal(java(scenario, dir, id, join(work, 'renewed_client.der'), join(work, 'ca.der')).trim(), 'rejected-verified');
}
console.log('✓ Renewal rejects authority/profile replacement and certificate replay without modifying enrollment');
assert.equal(java('test-blocked', dir, id).trim(), 'blocked-verified');
console.log('✓ Temporary block preserves enrollment and schedules retry');

// Test 2: Revocation fails closed immediately and cleans active.json
const res2 = java('test-revoked', dir, id);
assert.equal(res2.trim(), 'revoked-verified');
console.log('✓ Revocation handling succeeded: active.json deleted, state REVOKED, transport unauthorized');

// Test 3: Expired certificate fails closed
// Recreate active.json with expired timestamp
const expiredLeafDer = initialLeafDer;
const expiredActive = {
  ...activeJson,
  expires_at: Date.now() - 3600000 // Expired 1 hour ago
};
writeFileSync(join(dir, 'active.json'), JSON.stringify(expiredActive));
// Also generate an expired certificate with OpenSSL
// openssl ca supports explicit validity dates on OpenSSL 3.0 (CI) as well as 3.5.
mkdirSync(join(work, 'issued'));
writeFileSync(join(work, 'index.txt'), '');
writeFileSync(join(work, 'serial'), '03\n');
writeFileSync(join(work, 'expired.cnf'), `[ca]
default_ca=test
[test]
database=index.txt
new_certs_dir=issued
certificate=ca.pem
private_key=ca.key
serial=serial
default_md=sha256
default_days=1
policy=names
x509_extensions=client
[names]
commonName=supplied
[client]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
`);
openssl('ca', '-batch', '-config', 'expired.cnf', '-in', 'request.pem', '-startdate', '20200101000000Z', '-enddate', '20200102000000Z', '-notext', '-out', 'expired_client.pem');
openssl('x509', '-in', 'expired_client.pem', '-outform', 'DER', '-out', 'expired_client.der');
expiredActive.certificate_base64 = readFileSync(join(work, 'expired_client.der')).toString('base64');
writeFileSync(join(dir, 'active.json'), JSON.stringify(expiredActive));

const res3 = java('test-expired', dir, id);
assert.equal(res3.trim(), 'expired-verified');
console.log('✓ Expired certificate fails closed: remote transport strictly unauthorized without public fallback');

console.log('All autonomous renewal scheduler tests passed!');
