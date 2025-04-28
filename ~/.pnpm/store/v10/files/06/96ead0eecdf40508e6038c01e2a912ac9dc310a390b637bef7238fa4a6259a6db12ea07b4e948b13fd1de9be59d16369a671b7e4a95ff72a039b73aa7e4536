import * as _unhead_schema from '@unhead/schema';
import { Head, CreateHeadOptions, Unhead, MergeHead, HeadEntryOptions, ActiveHeadEntry, HeadSafe, ScriptInstance, AsAsyncFunctionValues, UseScriptResolvedInput, UseScriptInput, UseScriptOptions, UseFunctionType, UseSeoMetaInput } from '@unhead/schema';
export { composableNames } from '@unhead/shared';

declare function createHead<T extends {} = Head>(options?: CreateHeadOptions): Unhead<T>;
declare function createServerHead<T extends {} = Head>(options?: CreateHeadOptions): Unhead<T>;
/**
 * Creates a core instance of unhead. Does not provide a global ctx for composables to work
 * and does not register DOM plugins.
 *
 * @param options
 */
declare function createHeadCore<T extends {} = Head>(options?: CreateHeadOptions): Unhead<T>;

declare const unheadComposablesImports: {
    from: string;
    imports: string[];
}[];

declare function getActiveHead(): _unhead_schema.Unhead<any> | undefined;

type UseHeadInput<T extends MergeHead> = Head<T>;
declare function useHead<T extends MergeHead>(input: UseHeadInput<T>, options?: HeadEntryOptions): ActiveHeadEntry<UseHeadInput<T>> | void;

declare function useHeadSafe(input: HeadSafe, options?: HeadEntryOptions): ActiveHeadEntry<HeadSafe> | void;

type UseScriptContext<T extends Record<symbol | string, any>> = (Promise<T> & ScriptInstance<T>) & AsAsyncFunctionValues<T> & {
    /**
     * @deprecated Use top-level functions instead.
     */
    $script: Promise<T> & ScriptInstance<T>;
};
declare function resolveScriptKey(input: UseScriptResolvedInput): any;
/**
 * Load third-party scripts with SSR support and a proxied API.
 *
 * @see https://unhead.unjs.io/usage/composables/use-script
 */
declare function useScript<T extends Record<symbol | string, any> = Record<symbol | string, any>, U = Record<symbol | string, any>>(_input: UseScriptInput, _options?: UseScriptOptions<T, U>): UseScriptContext<UseFunctionType<UseScriptOptions<T, U>, T>>;

declare function useSeoMeta(input: UseSeoMetaInput, options?: HeadEntryOptions): ActiveHeadEntry<any> | void;

declare function useServerHead<T extends MergeHead>(input: UseHeadInput<T>, options?: HeadEntryOptions): ActiveHeadEntry<UseHeadInput<T>> | void;

declare function useServerHeadSafe<T extends HeadSafe>(input: T, options?: HeadEntryOptions): ActiveHeadEntry<T> | void;

declare function useServerSeoMeta(input: UseSeoMetaInput, options?: HeadEntryOptions): ActiveHeadEntry<any> | void;

declare function CapoPlugin(options: {
    track?: boolean;
}): _unhead_schema.HeadPluginInput;

/**
 * @deprecated Hash hydration is no longer supported. Please remove this plugin.
 */
declare function HashHydrationPlugin(): _unhead_schema.HeadPluginInput;

export { CapoPlugin, HashHydrationPlugin, type UseHeadInput, type UseScriptContext, createHead, createHeadCore, createServerHead, getActiveHead, resolveScriptKey, unheadComposablesImports, useHead, useHeadSafe, useScript, useSeoMeta, useServerHead, useServerHeadSafe, useServerSeoMeta };
