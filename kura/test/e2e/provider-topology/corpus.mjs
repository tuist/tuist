import crypto from "node:crypto";

export const bodySize = 1024 * 1024;
export function bodyFor(key) {
  return crypto.createHash("shake256", { outputLength: bodySize }).update("kura-resource-v2:" + key).digest();
}
