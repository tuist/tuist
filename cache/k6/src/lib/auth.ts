import http from 'k6/http';
import { check } from 'k6';
import { SERVER_URL, AUTH_EMAIL, AUTH_PASSWORD } from '../config.ts';

export function authenticate(): string {
  var res = http.post(
    SERVER_URL + '/api/auth',
    JSON.stringify({ email: AUTH_EMAIL, password: AUTH_PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  var ok = check(res, {
    'auth: status 200': function (r) { return r.status === 200; },
    'auth: has access_token': function (r) { return !!(r.json() as any).access_token; },
  });

  if (!ok) {
    throw new Error('Authentication failed: ' + res.status + ' ' + res.body);
  }

  return (res.json() as any).access_token as string;
}
