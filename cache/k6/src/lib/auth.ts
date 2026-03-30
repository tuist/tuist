import { CACHE_AUTH_TOKEN } from '../config.ts';

export function authToken(): string {
  if (!CACHE_AUTH_TOKEN) {
    throw new Error('Missing CACHE_AUTH_TOKEN environment variable');
  }

  return CACHE_AUTH_TOKEN;
}
