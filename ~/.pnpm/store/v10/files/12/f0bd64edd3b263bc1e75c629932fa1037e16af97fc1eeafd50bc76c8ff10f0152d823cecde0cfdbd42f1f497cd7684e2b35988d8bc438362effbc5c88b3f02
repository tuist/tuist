import type { UnknownObject } from '@scalar/types/utils';
import { stringify } from 'yaml';
type PrimitiveOrObject = object | string | null | number | boolean | undefined;
/** Yaml handling with optional safeparse */
export declare const yaml: {
    /** Parse and throw if the return value is not an object */
    parse: (val: string) => UnknownObject;
    /** Parse and return a fallback on failure */
    parseSafe<T extends PrimitiveOrObject>(val: string, fallback: T | ((err: any) => T)): UnknownObject | T;
    stringify: typeof stringify;
};
/** JSON handling with optional safeparse */
export declare const json: {
    /** Parse and throw if the return value is not an object */
    parse: (val: string) => UnknownObject;
    /** Parse and return a fallback on failure */
    parseSafe<T extends PrimitiveOrObject>(val: string, fallback: T | ((err: any) => T)): UnknownObject | T;
    stringify: (val: object) => string;
};
/**
 * Check if value is a valid JSON string
 */
export declare const isJsonString: (value?: any) => boolean;
/**
 * This helper is used to transform the content of the swagger file to JSON, even it was YAML.
 */
export declare const transformToJson: (value: string) => string;
/** Validates a JSON string if provided. Otherwise returns the raw YAML */
export declare function formatJsonOrYamlString(value: string): string;
/** Parse JSON or YAML into an object */
export declare const parseJsonOrYaml: (value: string | UnknownObject) => UnknownObject;
export {};
//# sourceMappingURL=parse.d.ts.map