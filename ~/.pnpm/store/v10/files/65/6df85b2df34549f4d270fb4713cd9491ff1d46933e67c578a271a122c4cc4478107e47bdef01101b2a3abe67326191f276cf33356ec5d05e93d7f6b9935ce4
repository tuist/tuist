import type { Response } from "undici";
import type { JRef, JRefType } from "./jref/index.js";


// Browser
export type Browser<T extends Document = Document> = {
  uri: string;
  document: T;
  cursor: string;
};

export type Document = {
  baseUri: string;
  root: JRef;
  anchorLocation: (anchor: string | undefined) => string;
  embedded?: Record<string, Document>;
};

export const get: <T extends Document>(uri: string, browser?: Browser) => Promise<Browser<T>>;
export const value: <T>(browser: Browser) => T;
export const typeOf: (browser: Browser) => JRefType;
export const has: (key: string, browser: Browser) => boolean;
export const length: (browser: Browser) => number;
export const step: (key: string, browser: Browser) => Promise<Browser>;
export const iter: (browser: Browser) => AsyncGenerator<Browser>;
export const keys: (browser: Browser) => Generator<string>;
export const values: (browser: Browser) => AsyncGenerator<Browser>;
export const entries: (browser: Browser) => AsyncGenerator<[string, Browser]>;

export class RetrievalError extends Error {
  public constructor(message: string, cause: Error);
  public get cause(): Error;
}

// Media Types
export type MediaTypePlugin<T extends Document = Document> = {
  parse: (response: Response) => Promise<T>;
  fileMatcher: (path: string) => Promise<boolean>;
  quality?: number;
};

export const addMediaTypePlugin: (contentType: string, plugin: MediaTypePlugin) => void;
export const removeMediaTypePlugin: (contentType: string) => void;
export const setMediaTypeQuality: (contentType: string, quality: number) => void;
export const acceptableMediaTypes: () => string;

export class UnsupportedMediaTypeError extends Error {
  public constructor(mediaType: string, message?: string);
  public get mediaType(): string;
}

export class UnknownMediaTypeError extends Error {
  public constructor(message?: string);
}

// URI Schemes
export type UriSchemePlugin = {
  retrieve: typeof retrieve;
};

export const retrieve: (uri: string, baseUri?: string) => Promise<Response>;
export const addUriSchemePlugin: (scheme: string, plugin: UriSchemePlugin) => void;
export const removeUriSchemePlugin: (scheme: string) => void;

export class UnsupportedUriSchemeError extends Error {
  public constructor(scheme: string, message?: string);
  public get scheme(): string;
}
