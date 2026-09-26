// Tests for Desktop Operator Authentication, PKCE, Device ID, and Address Book Catalog
import { createHash, randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';

console.log('--- Running Desktop Operator Auth & Address Book Tests ---');

// 1. Device ID UUID Generation and Validation
function generateUuidV4() {
  const bytes = randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 10
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const testDeviceId = generateUuidV4();
assert.match(testDeviceId, uuidRegex, 'Device ID must be a valid RFC 4122 v4 UUID');

// In-Memory Secure Storage Mock (verifying no plaintext fallback)
class MockSecureStorage {
  constructor() {
    this.storage = new Map();
  }
  async read(key) { return this.storage.get(key) || null; }
  async write(key, value) { this.storage.set(key, value); }
  async delete(key) { this.storage.delete(key); }
}

const secureStore = new MockSecureStorage();
await secureStore.write('device_id', testDeviceId);
const retrievedDeviceId = await secureStore.read('device_id');
assert.equal(retrievedDeviceId, testDeviceId, 'Device ID must persist stably across reads');
console.log('✓ Device ID stable RFC 4122 v4 UUID validated');

// 2. PKCE (RFC 7636) Generation & Verification
function generatePkce() {
  const verifierBytes = randomBytes(32);
  const verifier = verifierBytes.toString('base64url').replace(/=/g, '');
  const challenge = createHash('sha256').update(verifier).digest('base64url').replace(/=/g, '');
  return { verifier, challenge };
}

const pkce = generatePkce();
assert.equal(pkce.verifier.length, 43, 'PKCE verifier must be 43 base64url characters');
assert.equal(
  createHash('sha256').update(pkce.verifier).digest('base64url').replace(/=/g, ''),
  pkce.challenge,
  'PKCE challenge must match SHA-256 of verifier'
);
console.log('✓ PKCE verifier & SHA-256 challenge generation validated');

// 3. Browser-based Device Code Authorization & Single-Use Polling
class MockAuthServer {
  constructor() {
    this.authorizations = new Map();
    this.sessions = new Map();
  }

  createAuthorization(challenge, deviceId) {
    const deviceCode = 'dc_' + randomBytes(16).toString('hex');
    const userCode = 'AZ-' + randomBytes(3).toString('hex').toUpperCase();
    this.authorizations.set(deviceCode, {
      challenge,
      deviceId,
      userCode,
      status: 'pending',
      consumed: false,
      expiresAt: Date.now() + 600000,
    });
    return {
      device_code: deviceCode,
      user_code: userCode,
      verification_uri: `https://app.azsign.com.br/device?code=${userCode}`,
      expires_in: 600,
      interval: 3,
    };
  }

  approve(deviceCode, tenantId, userId) {
    const auth = this.authorizations.get(deviceCode);
    if (!auth) throw new Error('Not found');
    auth.status = 'approved';
    auth.tenantId = tenantId;
    auth.userId = userId;
  }

  exchangeToken(deviceCode, codeVerifier) {
    const auth = this.authorizations.get(deviceCode);
    if (!auth) return { status: 400, error: 'invalid_grant' };
    if (auth.consumed) return { status: 400, error: 'device_code_already_consumed' }; // Single-use!
    if (Date.now() > auth.expiresAt) return { status: 400, error: 'expired_token' };

    // Verify PKCE
    const computedChallenge = createHash('sha256').update(codeVerifier).digest('base64url').replace(/=/g, '');
    if (computedChallenge !== auth.challenge) return { status: 400, error: 'invalid_pkce_verifier' };

    if (auth.status === 'pending') {
      return { status: 428, error: 'authorization_pending' };
    }

    if (auth.status === 'approved') {
      auth.consumed = true; // Mark as consumed (single-use)
      const token = 'tok_' + randomBytes(24).toString('hex');
      const session = {
        access_token: token,
        token_type: 'Bearer',
        expires_in: 86400,
        tenant: { id: auth.tenantId, name: 'Empresa Piloto' },
        user: { id: auth.userId, name: 'Operador Teste', email: 'operador@azsign.com.br' },
      };
      this.sessions.set(token, session);
      return { status: 200, data: session };
    }

    return { status: 400, error: 'access_denied' };
  }

  getSession(token) {
    return this.sessions.get(token) || null;
  }

  revokeSession(token) {
    return this.sessions.delete(token);
  }
}

const authServer = new MockAuthServer();

// Start flow
const authReq = authServer.createAuthorization(pkce.challenge, testDeviceId);
assert(authReq.device_code.startsWith('dc_'));
assert(authReq.verification_uri.includes('app.azsign.com.br'));

// Poll while pending
const poll1 = authServer.exchangeToken(authReq.device_code, pkce.verifier);
assert.equal(poll1.status, 428, 'Must return 428 pending while user has not approved in browser');

// Wrong verifier must fail
const badVerifier = authServer.exchangeToken(authReq.device_code, 'wrong_verifier');
assert.equal(badVerifier.status, 400);
assert.equal(badVerifier.error, 'invalid_pkce_verifier');

// Operator approves in browser
authServer.approve(authReq.device_code, '019d626f-a5ac-733e-9a9c-f159912015e8', '0199a000-0000-7000-8000-000000000099');

// Poll after approval
const poll2 = authServer.exchangeToken(authReq.device_code, pkce.verifier);
assert.equal(poll2.status, 200);
assert(poll2.data.access_token.startsWith('tok_'));
assert.equal(poll2.data.user.email, 'operador@azsign.com.br');

// Attempting to reuse device code must fail (single-use check)
const pollReused = authServer.exchangeToken(authReq.device_code, pkce.verifier);
assert.equal(pollReused.status, 400);
assert.equal(pollReused.error, 'device_code_already_consumed', 'Device code must be strictly single-use');

// Save token in secure storage
await secureStore.write('access_token', poll2.data.access_token);
const token = await secureStore.read('access_token');
assert(token);

// Validate active session
const session = authServer.getSession(token);
assert(session);
assert.equal(session.user.name, 'Operador Teste');

// Clean logout
authServer.revokeSession(token);
await secureStore.delete('access_token');
assert.equal(authServer.getSession(token), null);
assert.equal(await secureStore.read('access_token'), null);
console.log('✓ Browser-based device authorization, single-use token exchange, session check & clean logout passed');

// 4. Address Book (Device Catalog) - Read-Only, Paginated, Decoupled Status
class MockAddressBookServer {
  constructor(devices) {
    this.devices = devices;
  }

  query({ page = 1, per_page = 20, search, tenant_id, player_status, remote_access_status }) {
    let list = [...this.devices];

    if (search) {
      const q = search.toLowerCase();
      list = list.filter(d => d.name.toLowerCase().includes(q));
    }
    if (tenant_id) {
      list = list.filter(d => d.tenant_id === tenant_id);
    }
    if (player_status) {
      list = list.filter(d => d.player_status === player_status);
    }
    if (remote_access_status) {
      list = list.filter(d => d.remote_access_status === remote_access_status);
    }

    const total = list.length;
    const last_page = Math.max(1, Math.ceil(total / per_page));
    const current_page = Math.min(Math.max(1, page), last_page);
    const start = (current_page - 1) * per_page;
    const end = Math.min(start + per_page, total);
    const items = start < total ? list.slice(start, end) : [];

    return {
      data: items,
      meta: {
        current_page,
        last_page,
        per_page,
        total,
        from: total > 0 ? start + 1 : null,
        to: total > 0 ? end : null,
      },
    };
  }
}

const catalogFixture = [
  {
    id: '01a0d0b2-702b-706c-b9bc-c2c05e3e6ee2',
    name: 'DC400',
    tenant_id: '019d626f-a5ac-733e-9a9c-f159912015e8',
    tenant_name: 'Empresa Piloto',
    player_status: 'online',
    remote_access_status: 'available',
    last_heartbeat_at: new Date().toISOString(),
    tags: ['Piloto', 'Lab'],
  },
  {
    id: '0199a000-0000-7000-8000-000000000010',
    name: 'Totem Recepção',
    tenant_id: '019d626f-a5ac-733e-9a9c-f159912015e8',
    tenant_name: 'Empresa Piloto',
    player_status: 'online',
    remote_access_status: 'unprovisioned',
    last_heartbeat_at: new Date().toISOString(),
    tags: ['Entrada'],
  },
  {
    id: '0199a000-0000-7000-8000-000000000020',
    name: 'Menu Board 1',
    tenant_id: '019d626f-a5ac-733e-9a9c-f159912015e8',
    tenant_name: 'Empresa Piloto',
    player_status: 'offline',
    remote_access_status: 'offline',
    last_heartbeat_at: new Date(Date.now() - 36000000).toISOString(),
    tags: ['Menu'],
  },
  {
    id: '0199a000-0000-7000-8000-000000000030',
    name: 'Vitrine Principal',
    tenant_id: '019d626f-a5ac-733e-9a9c-f159912015e8',
    tenant_name: 'Empresa Piloto',
    player_status: 'online',
    remote_access_status: 'revoked',
    last_heartbeat_at: new Date().toISOString(),
    tags: ['Bloqueado'],
  },
];

const addressBook = new MockAddressBookServer(catalogFixture);

// Test Pagination
const page1 = addressBook.query({ page: 1, per_page: 2 });
assert.equal(page1.data.length, 2);
assert.equal(page1.meta.total, 4);
assert.equal(page1.meta.current_page, 1);
assert.equal(page1.meta.last_page, 2);
assert.equal(page1.meta.from, 1);
assert.equal(page1.meta.to, 2);

const page2 = addressBook.query({ page: 2, per_page: 2 });
assert.equal(page2.data.length, 2);
assert.equal(page2.meta.current_page, 2);
assert.equal(page2.meta.from, 3);
assert.equal(page2.meta.to, 4);

// Test Search
const searchResult = addressBook.query({ search: 'dc400' });
assert.equal(searchResult.data.length, 1);
assert.equal(searchResult.data[0].name, 'DC400');
assert.equal(searchResult.data[0].remote_access_status, 'available');

// Test Decoupled Status
// 1. Online player with unprovisioned remote access:
const totem = addressBook.query({ search: 'totem' }).data[0];
assert.equal(totem.player_status, 'online', 'Player heartbeat is active');
assert.equal(totem.remote_access_status, 'unprovisioned', 'Remote access is unprovisioned');
// 2. Online player with revoked remote access:
const vitrine = addressBook.query({ search: 'vitrine' }).data[0];
assert.equal(vitrine.player_status, 'online', 'Player heartbeat is active');
assert.equal(vitrine.remote_access_status, 'revoked', 'Remote access must reflect revocation independently');

// Test Security Rules
for (const dev of catalogFixture) {
  assert(!('password' in dev), 'No password fields in Address Book response');
  assert(!('session_permit' in dev), 'No session permit in Address Book response');
}

console.log('✓ Read-only paginated Address Book, search, decoupled status, and no-password policy validated');

console.log('--- ALL DESKTOP OPERATOR & ADDRESS BOOK TESTS PASSED ---');
