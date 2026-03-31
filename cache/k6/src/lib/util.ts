import { SizeBucket } from '../types.ts';

export function weightedRandom(items: SizeBucket[]): SizeBucket {
  const rand = Math.random();
  let cumulative = 0;
  for (const item of items) {
    cumulative += item.weight;
    if (rand < cumulative) return item;
  }
  return items[items.length - 1];
}

export function randomItem<T>(items: T[]): T {
  return items[Math.floor(Math.random() * items.length)];
}

export function randomId(): string {
  const chars = 'abcdef0123456789';
  let result = '';
  for (let i = 0; i < 16; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export function randomString(length: number): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}
