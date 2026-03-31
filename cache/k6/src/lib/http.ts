import { CACHE_BASE_URL, ACCOUNT_HANDLE, PROJECT_HANDLE } from '../config.ts';

export function authHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

export function cacheUrl(path: string, extra?: Record<string, string>): string {
  const params: Record<string, string> = {
    account_handle: ACCOUNT_HANDLE,
    project_handle: PROJECT_HANDLE,
    ...extra,
  };
  const query = Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
  return `${CACHE_BASE_URL}${path}?${query}`;
}
