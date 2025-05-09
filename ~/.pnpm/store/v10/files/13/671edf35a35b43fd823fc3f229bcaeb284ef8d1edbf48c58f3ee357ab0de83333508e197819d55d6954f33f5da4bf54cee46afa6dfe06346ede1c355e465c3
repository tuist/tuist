import type { AnyApiDefinitionFormat, Filesystem, LoadResult, ThrowOnErrorOption } from '../../types/index.ts';
export type LoadPlugin = {
    check: (value?: any) => boolean;
    get: (value: any) => any;
    resolvePath?: (value: any, reference: string) => string;
    getDir?: (value: any) => string;
    getFilename?: (value: any) => string;
};
export type LoadOptions = {
    plugins?: LoadPlugin[];
    filename?: string;
    filesystem?: Filesystem;
} & ThrowOnErrorOption;
/**
 * Loads an OpenAPI document, including any external references.
 *
 * This function handles loading content from various sources, normalizes the content,
 * and recursively loads any external references found within the definition.
 *
 * It builds a filesystem representation of all loaded content and collects any errors
 * encountered during the process.
 */
export declare function load(value: AnyApiDefinitionFormat, options?: LoadOptions): Promise<LoadResult>;
//# sourceMappingURL=load.d.ts.map