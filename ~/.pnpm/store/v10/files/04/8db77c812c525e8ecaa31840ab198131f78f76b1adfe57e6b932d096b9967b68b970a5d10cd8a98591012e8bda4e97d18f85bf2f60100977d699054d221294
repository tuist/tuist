import { HeadPluginInput, HeadTag, BaseMeta, MetaFlatInput, Head, HeadEntry, MaybeArray, HeadSafe, TemplateParams } from '@unhead/schema';

type Arrayable<T> = T | Array<T>;
declare function asArray<T>(value: Arrayable<T>): T[];

declare const SelfClosingTags: Set<string>;
declare const TagsWithInnerContent: Set<string>;
declare const HasElementTags: Set<string>;
declare const ValidHeadTags: Set<string>;
declare const UniqueTags: Set<string>;
declare const TagConfigKeys: Set<string>;
declare const IsBrowser: boolean;
declare const composableNames: string[];

declare function defineHeadPlugin(plugin: HeadPluginInput): HeadPluginInput;

declare function hashCode(s: string): string;
declare function hashTag(tag: HeadTag): string;

declare function resolveMetaKeyType(key: string): keyof BaseMeta;
declare function resolveMetaKeyValue(key: string): string;
declare function resolvePackedMetaObjectValue(value: string, key: string): string;
/**
 * Converts a flat meta object into an array of meta entries.
 * @param input
 */
declare function unpackMeta<T extends MetaFlatInput>(input: T): Required<Head>['meta'];
/**
 * Convert an array of meta entries to a flat object.
 * @param inputs
 */
declare function packMeta<T extends Required<Head>['meta']>(inputs: T): MetaFlatInput;

type Thenable<T> = Promise<T> | T;
declare function thenable<T, R>(val: T, thenFn: (val: Awaited<T>) => R): Promise<R> | R;

declare function normaliseTag<T extends HeadTag>(tagName: T['tag'], input: HeadTag['props'] | string, e: HeadEntry<T>, normalizedProps?: HeadTag['props']): Thenable<T | T[]>;
declare function normaliseStyleClassProps<T extends 'class' | 'style'>(key: T, v: Required<Required<Head>['htmlAttrs']['class']> | Required<Required<Head>['htmlAttrs']['style']>): string;
declare function normaliseProps<T extends HeadTag>(props: T['props'], virtual?: boolean): Thenable<T['props']>;
declare const TagEntityBits = 10;
declare function normaliseEntryTags<T extends object = Head>(e: HeadEntry<T>): Thenable<HeadTag[]>;

declare function whitelistSafeInput(input: Record<string, MaybeArray<Record<string, string>>>): HeadSafe;

declare const NetworkEvents: Set<string>;
declare const ScriptNetworkEvents: Set<string>;

declare const TAG_WEIGHTS: {
    readonly base: -10;
    readonly title: 10;
};
declare const TAG_ALIASES: {
    readonly critical: -80;
    readonly high: -10;
    readonly low: 20;
};
declare function tagWeight<T extends HeadTag>(tag: T): number;
declare const SortModifiers: {
    prefix: string;
    offset: number;
}[];

declare function tagDedupeKey<T extends HeadTag>(tag: T): string | false;

declare function processTemplateParams(s: string, p: TemplateParams, sep: string, isJson?: boolean): string;

declare function resolveTitleTemplate(template: string | ((title?: string) => string | null) | null, title?: string): string | null;

export { type Arrayable, HasElementTags, IsBrowser, NetworkEvents, ScriptNetworkEvents, SelfClosingTags, SortModifiers, TAG_ALIASES, TAG_WEIGHTS, TagConfigKeys, TagEntityBits, TagsWithInnerContent, type Thenable, UniqueTags, ValidHeadTags, asArray, composableNames, defineHeadPlugin, hashCode, hashTag, normaliseEntryTags, normaliseProps, normaliseStyleClassProps, normaliseTag, packMeta, processTemplateParams, resolveMetaKeyType, resolveMetaKeyValue, resolvePackedMetaObjectValue, resolveTitleTemplate, tagDedupeKey, tagWeight, thenable, unpackMeta, whitelistSafeInput };
