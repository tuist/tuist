import { BaseHtmlAttr, MaybeArray, BaseBodyAttr, Title as Title$1, TitleTemplate as TitleTemplate$1, EntryAugmentation, Base as Base$1, Link as Link$1, Meta as Meta$1, Style as Style$1, Script as Script$1, Noscript as Noscript$1, DataKeys, SchemaAugmentations, DefinedValueOrEmptyObject, MaybeFunctionEntries, BodyEvents, MergeHead, HeadEntryOptions, MetaFlatInput, Unhead } from '@unhead/schema';
import { ComputedRef, Ref, Plugin } from 'vue';

type MaybeReadonlyRef<T> = (() => T) | ComputedRef<T>;
type MaybeComputedRef<T> = T | MaybeReadonlyRef<T> | Ref<T>;
type MaybeComputedRefOrFalsy<T> = undefined | false | null | T | MaybeReadonlyRef<T> | Ref<T>;
/**
 * @deprecated Use MaybeComputedRefOrFalsy
 */
type MaybeComputedRefOrPromise<T> = MaybeComputedRefOrFalsy<T>;
type MaybeComputedRefEntries<T> = MaybeComputedRef<T> | {
    [key in keyof T]?: MaybeComputedRefOrFalsy<T[key]>;
};
type MaybeComputedRefEntriesOnly<T> = {
    [key in keyof T]?: MaybeComputedRefOrFalsy<T[key]>;
};

interface HtmlAttr extends Omit<BaseHtmlAttr, 'class'> {
    /**
     * The class global attribute is a space-separated list of the case-sensitive classes of the element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/class
     */
    class?: MaybeArray<MaybeComputedRef<string>> | Record<string, MaybeComputedRef<boolean>>;
}
interface BodyAttr extends Omit<BaseBodyAttr, 'class' | 'style'> {
    /**
     * The class global attribute is a space-separated list of the case-sensitive classes of the element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/class
     */
    class?: MaybeArray<MaybeComputedRef<string>> | Record<string, MaybeComputedRef<boolean>>;
    /**
     * The class global attribute is a space-separated list of the case-sensitive classes of the element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/class
     */
    style?: MaybeArray<MaybeComputedRef<string>> | Record<string, MaybeComputedRef<string | boolean>>;
}
type Title = MaybeComputedRef<Title$1>;
type TitleTemplate = TitleTemplate$1 | Ref<TitleTemplate$1> | ((title?: string) => TitleTemplate$1);
type Base<E extends EntryAugmentation = {}> = MaybeComputedRef<MaybeComputedRefEntries<Base$1<E>>>;
type Link<E extends EntryAugmentation = {}> = MaybeComputedRefEntries<Link$1<E>>;
type Meta<E extends EntryAugmentation = {}> = MaybeComputedRefEntries<Meta$1<E>>;
type Style<E extends EntryAugmentation = {}> = MaybeComputedRefEntries<Style$1<E>>;
type Script<E extends EntryAugmentation = {}> = MaybeComputedRefEntries<Script$1<E>>;
type Noscript<E extends EntryAugmentation = {}> = MaybeComputedRefEntries<Noscript$1<E>>;
type HtmlAttributes<E extends EntryAugmentation = {}> = MaybeComputedRef<MaybeComputedRefEntries<HtmlAttr & DataKeys & SchemaAugmentations['htmlAttrs'] & DefinedValueOrEmptyObject<E>>>;
type BodyAttributes<E extends EntryAugmentation = {}> = MaybeComputedRef<MaybeComputedRefEntries<BodyAttr & DataKeys & SchemaAugmentations['bodyAttrs'] & DefinedValueOrEmptyObject<E>> & MaybeFunctionEntries<BodyEvents>>;
interface ReactiveHead<E extends MergeHead = MergeHead> {
    /**
     * The `<title>` HTML element defines the document's title that is shown in a browser's title bar or a page's tab.
     * It only contains text; tags within the element are ignored.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/title
     */
    title?: Title;
    /**
     * Generate the title from a template.
     */
    titleTemplate?: TitleTemplate;
    /**
     * Variables used to substitute in the title and meta content.
     */
    templateParams?: MaybeComputedRefEntries<{
        separator?: '|' | '-' | '·' | string;
    } & Record<string, null | string | MaybeComputedRefEntries<Record<string, null | string>>>>;
    /**
     * The `<base>` HTML element specifies the base URL to use for all relative URLs in a document.
     * There can be only one <base> element in a document.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/base
     */
    base?: Base<E['base']>;
    /**
     * The `<link>` HTML element specifies relationships between the current document and an external resource.
     * This element is most commonly used to link to stylesheets, but is also used to establish site icons
     * (both "favicon" style icons and icons for the home screen and apps on mobile devices) among other things.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/link#attr-as
     */
    link?: MaybeComputedRef<Link<E['link']>[]>;
    /**
     * The `<meta>` element represents metadata that cannot be expressed in other HTML elements, like `<link>` or `<script>`.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta
     */
    meta?: MaybeComputedRef<Meta<E['meta']>[]>;
    /**
     * The `<style>` HTML element contains style information for a document, or part of a document.
     * It contains CSS, which is applied to the contents of the document containing the `<style>` element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/style
     */
    style?: MaybeComputedRef<(Style<E['style']> | string)[]>;
    /**
     * The `<script>` HTML element is used to embed executable code or data; this is typically used to embed or refer to JavaScript code.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script
     */
    script?: MaybeComputedRef<(Script<E['script']> | string)[]>;
    /**
     * The `<noscript>` HTML element defines a section of HTML to be inserted if a script type on the page is unsupported
     * or if scripting is currently turned off in the browser.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/noscript
     */
    noscript?: MaybeComputedRef<(Noscript<E['noscript']> | string)[]>;
    /**
     * Attributes for the `<html>` HTML element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/html
     */
    htmlAttrs?: HtmlAttributes<E['htmlAttrs']>;
    /**
     * Attributes for the `<body>` HTML element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/body
     */
    bodyAttrs?: BodyAttributes<E['bodyAttrs']>;
}
type UseHeadOptions = Omit<HeadEntryOptions, 'head'> & {
    head?: VueHeadClient<any>;
};
type UseHeadInput<T extends MergeHead = {}> = MaybeComputedRef<ReactiveHead<T>>;
type UseSeoMetaInput = MaybeComputedRefEntriesOnly<MetaFlatInput> & {
    title?: ReactiveHead['title'];
    titleTemplate?: ReactiveHead['titleTemplate'];
};
type VueHeadClient<T extends MergeHead> = Unhead<MaybeComputedRef<ReactiveHead<T>>> & Plugin;

export type { BodyAttr as B, HtmlAttr as H, Link as L, MaybeComputedRefEntries as M, Noscript as N, ReactiveHead as R, Style as S, Title as T, UseHeadInput as U, VueHeadClient as V, MaybeComputedRef as a, UseHeadOptions as b, MaybeComputedRefEntriesOnly as c, UseSeoMetaInput as d, TitleTemplate as e, Base as f, Meta as g, Script as h, HtmlAttributes as i, BodyAttributes as j, MaybeReadonlyRef as k, MaybeComputedRefOrFalsy as l, MaybeComputedRefOrPromise as m };
