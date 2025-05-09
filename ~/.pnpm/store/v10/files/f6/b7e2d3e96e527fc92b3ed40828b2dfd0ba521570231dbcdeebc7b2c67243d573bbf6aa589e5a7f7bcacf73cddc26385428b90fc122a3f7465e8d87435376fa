export { CapoPlugin, HashHydrationPlugin, createHeadCore } from 'unhead';
import * as _unhead_schema from '@unhead/schema';
import { SafeMeta, SafeLink, SafeNoscript, SafeScript, SafeHtmlAttr, SafeBodyAttr, MergeHead, CreateHeadOptions, ActiveHeadEntry, ScriptInstance, UseScriptStatus, ScriptBase, DataKeys, SchemaAugmentations, HeadEntryOptions, UseScriptOptions as UseScriptOptions$1, AsAsyncFunctionValues, UseFunctionType } from '@unhead/schema';
export { ActiveHeadEntry, Head, HeadEntryOptions, HeadTag, MergeHead, Unhead } from '@unhead/schema';
import { R as ReactiveHead, M as MaybeComputedRefEntries, a as MaybeComputedRef, V as VueHeadClient, U as UseHeadInput, b as UseHeadOptions, c as MaybeComputedRefEntriesOnly, d as UseSeoMetaInput } from './shared/vue.fwis0K4Q.cjs';
export { f as Base, B as BodyAttr, j as BodyAttributes, H as HtmlAttr, i as HtmlAttributes, L as Link, l as MaybeComputedRefOrFalsy, m as MaybeComputedRefOrPromise, k as MaybeReadonlyRef, g as Meta, N as Noscript, h as Script, S as Style, T as Title, e as TitleTemplate } from './shared/vue.fwis0K4Q.cjs';
import { Ref, Plugin } from 'vue';

interface HeadSafe extends Pick<ReactiveHead, 'title' | 'titleTemplate' | 'templateParams'> {
    meta?: MaybeComputedRefEntries<SafeMeta>[];
    link?: MaybeComputedRefEntries<SafeLink>[];
    noscript?: MaybeComputedRefEntries<SafeNoscript>[];
    script?: MaybeComputedRefEntries<SafeScript>[];
    htmlAttrs?: MaybeComputedRefEntries<SafeHtmlAttr>;
    bodyAttrs?: MaybeComputedRefEntries<SafeBodyAttr>;
}
type UseHeadSafeInput = MaybeComputedRef<HeadSafe>;

declare function createServerHead<T extends MergeHead>(options?: Omit<CreateHeadOptions, 'domDelayFn' | 'document'>): VueHeadClient<T>;
declare function createHead<T extends MergeHead>(options?: CreateHeadOptions): VueHeadClient<T>;

declare function resolveUnrefHeadInput(ref: any): any;

declare const unheadVueComposablesImports: {
    '@unhead/vue': string[];
};

declare function setHeadInjectionHandler(handler: () => VueHeadClient<any> | undefined): void;
declare function injectHead<T extends MergeHead>(): VueHeadClient<T>;

declare function useHead<T extends MergeHead>(input: UseHeadInput<T>, options?: UseHeadOptions): ActiveHeadEntry<UseHeadInput<T>> | void;

declare function useHeadSafe(input: UseHeadSafeInput, options?: UseHeadOptions): ActiveHeadEntry<UseHeadSafeInput> | void;

interface VueScriptInstance<T extends Record<symbol | string, any>> extends Omit<ScriptInstance<T>, 'status'> {
    status: Ref<UseScriptStatus>;
}
type UseScriptInput = string | (MaybeComputedRefEntriesOnly<Omit<ScriptBase & DataKeys & SchemaAugmentations['script'], 'src'>> & {
    src: string;
});
interface UseScriptOptions<T extends Record<symbol | string, any> = {}, U = {}> extends HeadEntryOptions, Pick<UseScriptOptions$1<T, U>, 'use' | 'stub' | 'eventContext' | 'beforeInit'> {
    /**
     * The trigger to load the script:
     * - `undefined` | `client` - (Default) Load the script on the client when this js is loaded.
     * - `manual` - Load the script manually by calling `$script.load()`, exists only on the client.
     * - `Promise` - Load the script when the promise resolves, exists only on the client.
     * - `Function` - Register a callback function to load the script, exists only on the client.
     * - `server` - Have the script injected on the server.
     * - `ref` - Load the script when the ref is true.
     */
    trigger?: UseScriptOptions$1['trigger'] | Ref<boolean>;
}
type UseScriptContext<T extends Record<symbol | string, any>> = (Promise<T> & VueScriptInstance<T>) & AsAsyncFunctionValues<T> & {
    /**
     * @deprecated Use top-level functions instead.
     */
    $script: Promise<T> & VueScriptInstance<T>;
};
declare function useScript<T extends Record<symbol | string, any> = Record<symbol | string, any>, U = Record<symbol | string, any>>(_input: UseScriptInput, _options?: UseScriptOptions<T, U>): UseScriptContext<UseFunctionType<UseScriptOptions<T, U>, T>>;

declare function useSeoMeta(input: UseSeoMetaInput, options?: UseHeadOptions): ActiveHeadEntry<any> | void;

declare function useServerHead<T extends MergeHead>(input: UseHeadInput<T>, options?: UseHeadOptions): _unhead_schema.ActiveHeadEntry<MaybeComputedRef<ReactiveHead<any>>> | undefined;

declare function useServerHeadSafe(input: UseHeadSafeInput, options?: UseHeadOptions): void | _unhead_schema.ActiveHeadEntry<UseHeadSafeInput>;

declare function useServerSeoMeta(input: UseSeoMetaInput, options?: UseHeadOptions): ActiveHeadEntry<any> | void;

/**
 * @deprecated Import { UnheadPlugin } from `@unhead/vue/vue2` and use Vue.mixin(UnheadPlugin(head)) instead.
 */
declare const Vue2ProvideUnheadPlugin: Plugin;

declare const VueHeadMixin: {
    created(): void;
};

export { type HeadSafe, MaybeComputedRef, MaybeComputedRefEntries, MaybeComputedRefEntriesOnly, ReactiveHead, UseHeadInput, UseHeadOptions, type UseHeadSafeInput, type UseScriptContext, type UseScriptInput, type UseScriptOptions, UseSeoMetaInput, Vue2ProvideUnheadPlugin, VueHeadClient, VueHeadMixin, type VueScriptInstance, createHead, createServerHead, injectHead, resolveUnrefHeadInput, setHeadInjectionHandler, unheadVueComposablesImports, useHead, useHeadSafe, useScript, useSeoMeta, useServerHead, useServerHeadSafe, useServerSeoMeta };
