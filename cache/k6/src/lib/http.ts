import { CACHE_BASE_URL, ACCOUNT_HANDLE, PROJECT_HANDLE } from '../config.ts';

function buildQuery(params: Record<string, string>): string {
  var parts: string[] = [];
  var keys = Object.keys(params);
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i];
    parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(params[k]));
  }
  return parts.join('&');
}

export function authHeaders(token: string): Record<string, string> {
  return { Authorization: 'Bearer ' + token };
}

export function cacheUrl(path: string, extra?: Record<string, string>): string {
  var params: Record<string, string> = {
    account_handle: ACCOUNT_HANDLE,
    project_handle: PROJECT_HANDLE,
  };
  if (extra) {
    var keys = Object.keys(extra);
    for (var i = 0; i < keys.length; i++) {
      params[keys[i]] = extra[keys[i]];
    }
  }
  return CACHE_BASE_URL + path + '?' + buildQuery(params);
}
