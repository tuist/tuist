import { NestedHooks, Hookable } from 'hookable';
import { MergeHead, BaseBodyAttributes, HtmlAttributes as HtmlAttributes$1, Meta as Meta$1, Stringable, Merge, Base as Base$1, DefinedValueOrEmptyObject, LinkBase, HttpEventAttributes, DataKeys, Style as Style$1, ScriptBase, Noscript as Noscript$1, BodyEvents, MetaFlatInput } from 'zhead';
export { BodyEvents, DataKeys, DefinedValueOrEmptyObject, MergeHead, MetaFlatInput, ScriptBase, SpeculationRules } from 'zhead';

type Never<T> = {
    [P in keyof T]?: never;
};
type FalsyEntries<T> = {
    [key in keyof T]?: T[key] | null | false | undefined;
};

type UserTagConfigWithoutInnerContent = TagPriority & TagPosition & ResolvesDuplicates & Never<InnerContent> & {
    processTemplateParams?: false;
};
type UserAttributesConfig = ResolvesDuplicates & TagPriority & Never<InnerContent & TagPosition>;
interface SchemaAugmentations extends MergeHead {
    title: TagPriority;
    titleTemplate: TagPriority;
    base: UserAttributesConfig;
    htmlAttrs: UserAttributesConfig;
    bodyAttrs: UserAttributesConfig;
    link: UserTagConfigWithoutInnerContent;
    meta: UserTagConfigWithoutInnerContent;
    style: TagUserProperties;
    script: TagUserProperties;
    noscript: TagUserProperties;
}
type MaybeArray<T> = T | T[];
type BaseBodyAttr = BaseBodyAttributes;
type BaseHtmlAttr = HtmlAttributes$1;
interface BodyAttr extends Omit<BaseBodyAttr, 'class'> {
    /**
     * The class global attribute is a space-separated list of the case-sensitive classes of the element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/class
     */
    class?: MaybeArray<string> | Record<string, boolean>;
}
interface HtmlAttr extends Omit<HtmlAttributes$1, 'class'> {
    /**
     * The class global attribute is a space-separated list of the case-sensitive classes of the element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/class
     */
    class?: MaybeArray<string> | Record<string, boolean>;
}
interface BaseMeta extends Omit<Meta$1, 'content'> {
    /**
     * This attribute contains the value for the http-equiv, name or property attribute, depending on which is used.
     *
     * You can provide an array of values to create multiple tags sharing the same name, property or http-equiv.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta#attr-content
     */
    content?: MaybeArray<Stringable> | null;
}
type EntryAugmentation = undefined | Record<string, any>;
type MaybeFunctionEntries<T> = {
    [key in keyof T]?: T[key] | ((e: Event) => void);
};
type TitleTemplateResolver = string | ((title?: string) => string | null);
type Title = string | FalsyEntries<({
    textContent: string;
} & SchemaAugmentations['title']) | null>;
type TitleTemplate = TitleTemplateResolver | null | ({
    textContent: TitleTemplateResolver;
} & SchemaAugmentations['titleTemplate']);
type Base<E extends EntryAugmentation = Record<string, any>> = Partial<Merge<SchemaAugmentations['base'], FalsyEntries<Base$1>>> & DefinedValueOrEmptyObject<E>;
type Link<E extends EntryAugmentation = Record<string, any>> = FalsyEntries<LinkBase> & MaybeFunctionEntries<HttpEventAttributes> & DataKeys & SchemaAugmentations['link'] & DefinedValueOrEmptyObject<E>;
type Meta<E extends EntryAugmentation = Record<string, any>> = FalsyEntries<BaseMeta> & DataKeys & SchemaAugmentations['meta'] & DefinedValueOrEmptyObject<E>;
type Style<E extends EntryAugmentation = Record<string, any>> = FalsyEntries<Style$1> & DataKeys & SchemaAugmentations['style'] & DefinedValueOrEmptyObject<E>;
type Script<E extends EntryAugmentation = Record<string, any>> = FalsyEntries<ScriptBase> & MaybeFunctionEntries<HttpEventAttributes> & DataKeys & SchemaAugmentations['script'] & DefinedValueOrEmptyObject<E>;
type Noscript<E extends EntryAugmentation = Record<string, any>> = FalsyEntries<Noscript$1> & DataKeys & SchemaAugmentations['noscript'] & DefinedValueOrEmptyObject<E>;
type HtmlAttributes<E extends EntryAugmentation = Record<string, any>> = FalsyEntries<HtmlAttr> & DataKeys & SchemaAugmentations['htmlAttrs'] & DefinedValueOrEmptyObject<E>;
type BodyAttributes<E extends EntryAugmentation = Record<string, any>> = FalsyEntries<BodyAttr> & MaybeFunctionEntries<BodyEvents> & DataKeys & SchemaAugmentations['bodyAttrs'] & DefinedValueOrEmptyObject<E>;
interface HeadUtils {
    /**
     * Generate the title from a template.
     *
     * Should include a `%s` placeholder for the title, for example `%s - My Site`.
     */
    titleTemplate?: TitleTemplate;
    /**
     * Variables used to substitute in the title and meta content.
     */
    templateParams?: TemplateParams;
}
interface Head<E extends MergeHead = SchemaAugmentations> extends HeadUtils {
    /**
     * The `<title>` HTML element defines the document's title that is shown in a browser's title bar or a page's tab.
     * It only contains text; tags within the element are ignored.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/title
     */
    title?: Title;
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
    link?: Link<E['link']>[];
    /**
     * The `<meta>` element represents metadata that cannot be expressed in other HTML elements, like `<link>` or `<script>`.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta
     */
    meta?: Meta<E['meta']>[];
    /**
     * The `<style>` HTML element contains style information for a document, or part of a document.
     * It contains CSS, which is applied to the contents of the document containing the `<style>` element.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/style
     */
    style?: (Style<E['style']> | string)[];
    /**
     * The `<script>` HTML element is used to embed executable code or data; this is typically used to embed or refer to JavaScript code.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script
     */
    script?: (Script<E['script']> | string)[];
    /**
     * The `<noscript>` HTML element defines a section of HTML to be inserted if a script type on the page is unsupported
     * or if scripting is currently turned off in the browser.
     *
     * @see https://developer.mozilla.org/en-US/docs/Web/HTML/Element/noscript
     */
    noscript?: (Noscript<E['noscript']> | string)[];
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
type UseSeoMetaInput = MetaFlatInput & {
    title?: Title;
    titleTemplate?: TitleTemplate;
};

interface ResolvesDuplicates {
    /**
     * By default, tags which share the same unique key `name`, `property` are de-duped. To allow duplicates
     * to be made you can provide a unique key for each entry.
     */
    key?: string;
    /**
     * The strategy to use when a duplicate tag is encountered.
     *
     * - `replace` - Replace the existing tag with the new tag
     * - `merge` - Merge the existing tag with the new tag
     *
     * @default 'replace' (some tags will default to 'merge', such as htmlAttr)
     */
    tagDuplicateStrategy?: 'replace' | 'merge';
    /**
     * @deprecated Use `key` instead
     */
    hid?: string;
    /**
     * @deprecated Use `key` instead
     */
    vmid?: string;
}
type ValidTagPositions = 'head' | 'bodyClose' | 'bodyOpen';
interface TagPosition {
    /**
     * Specify where to render the tag.
     *
     * @default 'head'
     */
    tagPosition?: ValidTagPositions;
}
type InnerContentVal = string | Record<string, any>;
interface InnerContent {
    /**
     * Text content of the tag.
     *
     * Warning: This is not safe for XSS. Do not use this with user input, use `textContent` instead.
     */
    innerHTML?: InnerContentVal;
    /**
     * Sets the textContent of an element. Safer for XSS.
     */
    textContent?: InnerContentVal;
    /**
     * Sets the textContent of an element.
     *
     * @deprecated Use `textContent` or `innerHTML`.
     */
    children?: InnerContentVal;
}
interface TagPriority {
    /**
     * The priority for rendering the tag, without this all tags are rendered as they are registered
     * (besides some special tags).
     *
     * The following special tags have default priorities:
     * -2 `<meta charset ...>`
     * -1 `<base>`
     * 0 `<meta http-equiv="content-security-policy" ...>`
     *
     * All other tags have a default priority of 10: `<meta>`, `<script>`, `<link>`, `<style>`, etc
     */
    tagPriority?: number | 'critical' | 'high' | 'low' | `before:${string}` | `after:${string}`;
}
type TagUserProperties = FalsyEntries<TagPriority & TagPosition & InnerContent & ResolvesDuplicates & ProcessesTemplateParams>;
type TagKey = keyof Head;
type TemplateParams = {
    separator?: '|' | '-' | '·' | string;
} & Record<string, null | string | Record<string, string>>;
interface ProcessesTemplateParams {
    processTemplateParams?: boolean;
}
interface HasTemplateParams {
    templateParams?: TemplateParams;
}
interface HeadTag extends TagPriority, TagPosition, ResolvesDuplicates, HasTemplateParams {
    tag: TagKey;
    props: Record<string, string>;
    processTemplateParams?: boolean;
    innerHTML?: string;
    textContent?: string;
    /**
     * Entry ID
     * @internal
     */
    _e?: number;
    /**
     * Position
     * @internal
     */
    _p?: number;
    /**
     * Dedupe key
     * @internal
     */
    _d?: string;
    /**
     * Hash code used to represent the tag.
     * @internal
     */
    _h?: string;
    /**
     * @internal
     */
    _m?: RuntimeMode;
    /**
     * @internal
     */
    _eventHandlers?: Record<string, ((e: Event) => {})>;
}
type HeadTagKeys = (keyof HeadTag)[];

type HookResult = Promise<void> | void;
interface SSRHeadPayload {
    headTags: string;
    bodyTags: string;
    bodyTagsOpen: string;
    htmlAttrs: string;
    bodyAttrs: string;
}
interface RenderSSRHeadOptions {
    omitLineBreaks?: boolean;
}
interface EntryResolveCtx<T> {
    tags: HeadTag[];
    entries: HeadEntry<T>[];
}
interface DomRenderTagContext {
    id: string;
    $el: Element;
    shouldRender: boolean;
    tag: HeadTag;
    entry?: HeadEntry<any>;
    markSideEffect: (key: string, fn: () => void) => void;
}
interface DomBeforeRenderCtx extends ShouldRenderContext {
    /**
     * @deprecated will always be empty, prefer other hooks
     */
    tags: DomRenderTagContext[];
}
interface ShouldRenderContext {
    shouldRender: boolean;
}
interface SSRRenderContext {
    tags: HeadTag[];
    html: SSRHeadPayload;
}
interface HeadHooks {
    'init': (ctx: Unhead<any>) => HookResult;
    'entries:updated': (ctx: Unhead<any>) => HookResult;
    'entries:resolve': (ctx: EntryResolveCtx<any>) => HookResult;
    'tag:normalise': (ctx: {
        tag: HeadTag;
        entry: HeadEntry<any>;
        resolvedOptions: CreateHeadOptions;
    }) => HookResult;
    'tags:beforeResolve': (ctx: {
        tags: HeadTag[];
    }) => HookResult;
    'tags:resolve': (ctx: {
        tags: HeadTag[];
    }) => HookResult;
    'tags:afterResolve': (ctx: {
        tags: HeadTag[];
    }) => HookResult;
    'dom:beforeRender': (ctx: DomBeforeRenderCtx) => HookResult;
    'dom:renderTag': (ctx: DomRenderTagContext, document: Document, track: any) => HookResult;
    'dom:rendered': (ctx: {
        renders: DomRenderTagContext[];
    }) => HookResult;
    'ssr:beforeRender': (ctx: ShouldRenderContext) => HookResult;
    'ssr:render': (ctx: {
        tags: HeadTag[];
    }) => HookResult;
    'ssr:rendered': (ctx: SSRRenderContext) => HookResult;
    'script:updated': (ctx: {
        script: ScriptInstance<any>;
    }) => HookResult;
    'script:instance-fn': (ctx: {
        script: ScriptInstance<any>;
        fn: string | symbol;
        exists: boolean;
    }) => HookResult;
}

/**
 * Side effects are mapped with a key and their cleanup function.
 *
 * For example, `meta:data-h-4h46h465`: () => { document.querySelector('meta[data-h-4h46h465]').remove() }
 */
type SideEffectsRecord = Record<string, () => void>;
type RuntimeMode = 'server' | 'client';
interface HeadEntry<Input> {
    /**
     * User provided input for the entry.
     */
    input: Input;
    /**
     * Optional resolved input which will be used if set.
     */
    resolvedInput?: Input;
    /**
     * The mode that the entry should be used in.
     *
     * @internal
     */
    mode?: RuntimeMode;
    /**
     * Transformer function for the entry.
     *
     * @internal
     */
    transform?: (input: Input) => Promise<Input> | Input;
    /**
     * Head entry index
     *
     * @internal
     */
    _i: number;
    /**
     * Default tag position.
     *
     * @internal
     */
    tagPosition?: TagPosition['tagPosition'];
    /**
     * Default tag priority.
     *
     * @internal
     */
    tagPriority?: TagPriority['tagPriority'];
}
type HeadPluginOptions = Omit<CreateHeadOptions, 'plugins'> & {
    mode?: RuntimeMode;
};
type HeadPluginInput = (HeadPluginOptions & {
    key?: string;
}) | ((head: Unhead) => HeadPluginOptions & {
    key?: string;
});
type HeadPlugin = HeadPluginOptions & {
    key?: string;
};
/**
 * An active head entry provides an API to manipulate it.
 */
interface ActiveHeadEntry<Input> {
    /**
     * Updates the entry with new input.
     *
     * Will first clear any side effects for previous input.
     */
    patch: (input: Input) => void;
    /**
     * Dispose the entry, removing it from the active head.
     *
     * Will queue side effects for removal.
     */
    dispose: () => void;
}
interface CreateHeadOptions {
    domDelayFn?: (fn: () => void) => void;
    document?: Document;
    plugins?: HeadPluginInput[];
    hooks?: NestedHooks<HeadHooks>;
}
interface HeadEntryOptions extends TagPosition, TagPriority, ProcessesTemplateParams, ResolvesDuplicates {
    mode?: RuntimeMode;
    transform?: (input: unknown) => unknown;
    head?: Unhead;
}
interface Unhead<Input extends {} = Head> {
    /**
     * Registered plugins.
     */
    plugins: HeadPlugin[];
    /**
     * The active head entries.
     */
    headEntries: () => HeadEntry<Input>[];
    /**
     * Create a new head entry.
     */
    push: (entry: Input, options?: HeadEntryOptions) => ActiveHeadEntry<Input>;
    /**
     * Resolve tags from head entries.
     */
    resolveTags: () => Promise<HeadTag[]>;
    /**
     * Exposed hooks for easier extension.
     */
    hooks: Hookable<HeadHooks>;
    /**
     * Resolved options
     */
    resolvedOptions: CreateHeadOptions;
    /**
     * Use a head plugin, loads the plugins hooks.
     */
    use: (plugin: HeadPluginInput) => void;
    /**
     * Is it a server-side render context.
     */
    ssr: boolean;
    /**
     * @internal
     */
    _dom?: DomState;
    /**
     * @internal
     */
    _domUpdatePromise?: Promise<void>;
    /**
     * @internal
     */
    _domDebouncedUpdatePromise?: Promise<void>;
    /**
     * @internal
     */
    dirty: boolean;
    /**
     * @internal
     */
    _scripts?: Record<string, any>;
    /**
     * @internal
     */
    _templateParams?: TemplateParams;
    /**
     * @internal
     */
    _separator?: string;
}
interface DomState {
    pendingSideEffects: SideEffectsRecord;
    sideEffects: SideEffectsRecord;
    elMap: Record<string, Element>;
}

type SafeBodyAttr = Pick<BodyAttr, 'id' | 'class'> & DataKeys;
type SafeHtmlAttr = Pick<HtmlAttr, 'id' | 'class' | 'lang' | 'dir'> & DataKeys;
type SafeMeta = Pick<Meta, 'id' | 'name' | 'property' | 'content' | 'charset'> & DataKeys;
type SafeLink = Pick<Link, 'color' | 'crossorigin' | 'fetchpriority' | 'href' | 'hreflang' | 'imagesizes' | 'imagesrcset' | 'integrity' | 'media' | 'referrerpolicy' | 'sizes' | 'id'> & {
    rel?: Omit<Link['rel'], 'stylesheet' | 'canonical' | 'modulepreload' | 'prerender' | 'preload' | 'prefetch'>;
    type?: 'audio/aac' | 'application/x-abiword' | 'application/x-freearc' | 'image/avif' | 'video/x-msvideo' | 'application/vnd.amazon.ebook' | 'application/octet-stream' | 'image/bmp' | 'application/x-bzip' | 'application/x-bzip2' | 'application/x-cdf' | 'application/x-csh' | 'text/csv' | 'application/msword' | 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' | 'application/vnd.ms-fontobject' | 'application/epub+zip' | 'application/gzip' | 'image/gif' | 'image/vnd.microsoft.icon' | 'text/calendar' | 'application/java-archive' | 'image/jpeg' | 'application/json' | 'application/ld+json' | 'audio/midi' | 'audio/x-midi' | 'audio/mpeg' | 'video/mp4' | 'video/mpeg' | 'application/vnd.apple.installer+xml' | 'application/vnd.oasis.opendocument.presentation' | 'application/vnd.oasis.opendocument.spreadsheet' | 'application/vnd.oasis.opendocument.text' | 'audio/ogg' | 'video/ogg' | 'application/ogg' | 'audio/opus' | 'font/otf' | 'image/png' | 'application/pdf' | 'application/x-httpd-php' | 'application/vnd.ms-powerpoint' | 'application/vnd.openxmlformats-officedocument.presentationml.presentation' | 'application/vnd.rar' | 'application/rtf' | 'application/x-sh' | 'image/svg+xml' | 'application/x-tar' | 'image/tiff' | 'video/mp2t' | 'font/ttf' | 'text/plain' | 'application/vnd.visio' | 'audio/wav' | 'audio/webm' | 'video/webm' | 'image/webp' | 'font/woff' | 'font/woff2' | 'application/xhtml+xml' | 'application/vnd.ms-excel' | 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' | 'text/xml' | 'application/atom+xml' | 'application/xml' | 'application/vnd.mozilla.xul+xml' | 'application/zip' | 'video/3gpp' | 'audio/3gpp' | 'video/3gpp2' | 'audio/3gpp2' | (string & Record<never, never>);
} & DataKeys;
type SafeScript = Pick<Script, 'id' | 'textContent'> & {
    type: 'application/json' | 'application/ld+json';
} & DataKeys;
type SafeNoscript = Pick<Noscript, 'id' | 'textContent'> & DataKeys;
interface HeadSafe extends Pick<Head, 'title' | 'titleTemplate' | 'templateParams'> {
    meta?: SafeMeta[];
    link?: SafeLink[];
    noscript?: SafeNoscript[];
    script?: SafeScript[];
    htmlAttrs?: SafeHtmlAttr;
    bodyAttrs?: SafeBodyAttr;
}

type UseScriptStatus = 'awaitingLoad' | 'loading' | 'loaded' | 'error' | 'removed';
/**
 * Either a string source for the script or full script properties.
 */
type UseScriptInput = string | (Omit<Script, 'src'> & {
    src: string;
});
type UseScriptResolvedInput = Omit<Script, 'src'> & {
    src: string;
};
type BaseScriptApi = Record<symbol | string, any>;
type AsAsyncFunctionValues<T extends BaseScriptApi> = {
    [key in keyof T]: T[key] extends any[] ? T[key] : T[key] extends (...args: infer A) => infer R ? (...args: A) => R extends Promise<any> ? R : Promise<R> : T[key] extends Record<any, any> ? AsAsyncFunctionValues<T[key]> : never;
};
interface ScriptInstance<T extends BaseScriptApi> {
    proxy: AsAsyncFunctionValues<T>;
    instance?: T;
    id: string;
    status: UseScriptStatus;
    entry?: ActiveHeadEntry<any>;
    load: () => Promise<T>;
    remove: () => boolean;
    setupTriggerHandler: (trigger: UseScriptOptions['trigger']) => void;
    onLoaded: (fn: (instance: T) => void | Promise<void>) => void;
    onError: (fn: (err?: Error) => void | Promise<void>) => void;
    /**
     * @internal
     */
    _triggerAbortController?: AbortController | null;
    /**
     * @internal
     */
    _triggerAbortPromise?: Promise<void>;
    /**
     * @internal
     */
    _triggerPromises?: Promise<void>[];
    /**
     * @internal
     */
    _cbs: {
        loaded: null | ((instance: T) => void | Promise<void>)[];
        error: null | ((err?: Error) => void | Promise<void>)[];
    };
}
type UseFunctionType<T, U> = T extends {
    use: infer V;
} ? V extends (...args: any) => any ? ReturnType<V> : U : U;
interface UseScriptOptions<T extends BaseScriptApi = {}, U = {}> extends HeadEntryOptions {
    /**
     * Resolve the script instance from the window.
     */
    use?: () => T | undefined | null;
    /**
     * Stub the script instance. Useful for SSR or testing.
     */
    stub?: ((ctx: {
        script: ScriptInstance<T>;
        fn: string | symbol;
    }) => any);
    /**
     * The trigger to load the script:
     * - `undefined` | `client` - (Default) Load the script on the client when this js is loaded.
     * - `manual` - Load the script manually by calling `$script.load()`, exists only on the client.
     * - `Promise` - Load the script when the promise resolves, exists only on the client.
     * - `Function` - Register a callback function to load the script, exists only on the client.
     * - `server` - Have the script injected on the server.
     */
    trigger?: 'client' | 'server' | 'manual' | Promise<boolean | void> | ((fn: any) => any) | null;
    /**
     * Context to run events with. This is useful in Vue to attach the current instance context before
     * calling the event, allowing the event to be reactive.
     */
    eventContext?: any;
    /**
     * Called before the script is initialized. Will not be triggered when the script is already loaded. This means
     * this is guaranteed to be called only once, unless the script is removed and re-added.
     */
    beforeInit?: () => void;
}

export type { ActiveHeadEntry, AsAsyncFunctionValues, Base, BaseBodyAttr, BaseHtmlAttr, BaseMeta, BodyAttr, BodyAttributes, CreateHeadOptions, DomBeforeRenderCtx, DomRenderTagContext, DomState, EntryAugmentation, EntryResolveCtx, HasTemplateParams, Head, HeadEntry, HeadEntryOptions, HeadHooks, HeadPlugin, HeadPluginInput, HeadPluginOptions, HeadSafe, HeadTag, HeadTagKeys, HeadUtils, HookResult, HtmlAttr, HtmlAttributes, InnerContent, InnerContentVal, Link, MaybeArray, MaybeFunctionEntries, Meta, Noscript, ProcessesTemplateParams, RenderSSRHeadOptions, ResolvesDuplicates, RuntimeMode, SSRHeadPayload, SSRRenderContext, SafeBodyAttr, SafeHtmlAttr, SafeLink, SafeMeta, SafeNoscript, SafeScript, SchemaAugmentations, Script, ScriptInstance, ShouldRenderContext, SideEffectsRecord, Style, TagKey, TagPosition, TagPriority, TagUserProperties, TemplateParams, Title, TitleTemplate, Unhead, UseFunctionType, UseScriptInput, UseScriptOptions, UseScriptResolvedInput, UseScriptStatus, UseSeoMetaInput, UserAttributesConfig, UserTagConfigWithoutInnerContent, ValidTagPositions };
