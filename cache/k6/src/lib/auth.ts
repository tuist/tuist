import http from 'k6/http';
import encoding from 'k6/encoding';
import { check } from 'k6';
import { SERVER_URL, AUTH_EMAIL, AUTH_PASSWORD } from '../config.ts';

var cachedToken: string | null = null;
var cachedTokenExpiresAt = 0;
var TOKEN_REFRESH_BUFFER_MS = 60 * 1000;

export function authenticate(): string {
  var res = http.post(
    SERVER_URL + '/api/auth',
    JSON.stringify({ email: AUTH_EMAIL, password: AUTH_PASSWORD }),
    {
      headers: { 'Content-Type': 'application/json' },
      responseType: 'text',
    }
  );

  var body = res.status === 200 ? (res.json() as any) : null;
  var accessToken = body ? body.access_token : null;

  var ok = check(res, {
    'auth: status 200': function (r) { return r.status === 200; },
    'auth: has access_token': function () { return !!accessToken; },
  });

  if (!ok) {
    throw new Error('Authentication failed: ' + res.status + ' ' + res.body);
  }

  return accessToken as string;
}

function tokenExpiresAt(token: string): number {
  var parts = token.split('.');
  if (parts.length < 2) return 0;

  var payloadJson = encoding.b64decode(parts[1], 'rawurl', 's');
  var payload = JSON.parse(payloadJson) as any;

  return payload && payload.exp ? payload.exp * 1000 : 0;
}

function tokenIsFresh(expiresAt: number): boolean {
  return expiresAt - Date.now() > TOKEN_REFRESH_BUFFER_MS;
}

export function getValidToken(currentToken?: string): string {
  if (cachedToken && tokenIsFresh(cachedTokenExpiresAt)) {
    return cachedToken;
  }

  if (currentToken) {
    var currentTokenExpiresAt = tokenExpiresAt(currentToken);
    if (tokenIsFresh(currentTokenExpiresAt)) {
      cachedToken = currentToken;
      cachedTokenExpiresAt = currentTokenExpiresAt;
      return currentToken;
    }
  }

  cachedToken = authenticate();
  cachedTokenExpiresAt = tokenExpiresAt(cachedToken);
  return cachedToken;
}
