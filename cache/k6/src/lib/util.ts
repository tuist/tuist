import { SizeBucket } from '../types.ts';

export function weightedRandom(items: SizeBucket[]): SizeBucket {
  var rand = Math.random();
  var cumulative = 0;
  for (var i = 0; i < items.length; i++) {
    cumulative += items[i].weight;
    if (rand < cumulative) return items[i];
  }
  return items[items.length - 1];
}

export function randomItem<T>(items: T[]): T {
  return items[Math.floor(Math.random() * items.length)];
}

export function randomId(): string {
  var chars = 'abcdef0123456789';
  var result = '';
  for (var i = 0; i < 16; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export function randomString(length: number): string {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  var result = '';
  for (var i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}
