/**
 * Sanitize a tree.
 *
 * @param {Readonly<Nodes>} node
 *   Unsafe tree.
 * @param {Readonly<Schema> | null | undefined} [options]
 *   Configuration (default: `defaultSchema`).
 * @returns {Nodes}
 *   New, safe tree.
 */
export function sanitize(node: Readonly<Nodes>, options?: Readonly<Schema> | null | undefined): Nodes;
/**
 * Definition for a property.
 */
export type PropertyDefinition = [string, ...Array<Exclude<Properties[keyof Properties], Array<any>> | RegExp>] | string;
/**
 * Schema that defines what nodes and properties are allowed.
 *
 * The default schema is `defaultSchema`, which follows how GitHub cleans.
 * If any top-level key is missing in the given schema, the corresponding
 * value of the default schema is used.
 *
 * To extend the standard schema with a few changes, clone `defaultSchema`
 * like so:
 *
 * ```js
 * import deepmerge from 'deepmerge'
 * import {h} from 'hastscript'
 * import {defaultSchema, sanitize} from 'hast-util-sanitize'
 *
 * // This allows `className` on all elements.
 * const schema = deepmerge(defaultSchema, {attributes: {'*': ['className']}})
 *
 * const tree = sanitize(h('div', {className: ['foo']}), schema)
 *
 * // `tree` still has `className`.
 * console.log(tree)
 * // {
 * //   type: 'element',
 * //   tagName: 'div',
 * //   properties: {className: ['foo']},
 * //   children: []
 * // }
 * ```
 */
export type Schema = {
    /**
     * Whether to allow comment nodes (default: `false`).
     *
     * For example:
     *
     * ```js
     * allowComments: true
     * ```
     */
    allowComments?: boolean | null | undefined;
    /**
     * Whether to allow doctype nodes (default: `false`).
     *
     * For example:
     *
     * ```js
     * allowDoctypes: true
     * ```
     */
    allowDoctypes?: boolean | null | undefined;
    /**
     * Map of tag names to a list of tag names which are required ancestors
     * (default: `defaultSchema.ancestors`).
     *
     * Elements with these tag names will be ignored if they occur outside of one
     * of their allowed parents.
     *
     * For example:
     *
     * ```js
     * ancestors: {
     * tbody: ['table'],
     * // …
     * tr: ['table']
     * }
     * ```
     */
    ancestors?: Record<string, Array<string>> | null | undefined;
    /**
     * Map of tag names to allowed property names (default:
     * `defaultSchema.attributes`).
     *
     * The special key `'*'` as a tag name defines property names allowed on all
     * elements.
     *
     * The special value `'data*'` as a property name can be used to allow all
     * `data` properties.
     *
     * For example:
     *
     * ```js
     * attributes: {
     * 'ariaDescribedBy', 'ariaLabel', 'ariaLabelledBy', …, 'href'
     * // …
     * '*': [
     * 'abbr',
     * 'accept',
     * 'acceptCharset',
     * // …
     * 'vAlign',
     * 'value',
     * 'width'
     * ]
     * }
     * ```
     *
     * Instead of a single string in the array, which allows any property value
     * for the field, you can use an array to allow several values.
     * For example, `input: ['type']` allows `type` set to any value on `input`s.
     * But `input: [['type', 'checkbox', 'radio']]` allows `type` when set to
     * `'checkbox'` or `'radio'`.
     *
     * You can use regexes, so for example `span: [['className', /^hljs-/]]`
     * allows any class that starts with `hljs-` on `span`s.
     *
     * When comma- or space-separated values are used (such as `className`), each
     * value in is checked individually.
     * For example, to allow certain classes on `span`s for syntax highlighting,
     * use `span: [['className', 'number', 'operator', 'token']]`.
     * This will allow `'number'`, `'operator'`, and `'token'` classes, but drop
     * others.
     */
    attributes?: Record<string, Array<PropertyDefinition>> | null | undefined;
    /**
     * List of property names that clobber (default: `defaultSchema.clobber`).
     *
     * For example:
     *
     * ```js
     * clobber: ['ariaDescribedBy', 'ariaLabelledBy', 'id', 'name']
     * ```
     */
    clobber?: Array<string> | null | undefined;
    /**
     * Prefix to use before clobbering properties (default:
     * `defaultSchema.clobberPrefix`).
     *
     * For example:
     *
     * ```js
     * clobberPrefix: 'user-content-'
     * ```
     */
    clobberPrefix?: string | null | undefined;
    /**
     * Map of *property names* to allowed protocols (default:
     * `defaultSchema.protocols`).
     *
     * This defines URLs that are always allowed to have local URLs (relative to
     * the current website, such as `this`, `#this`, `/this`, or `?this`), and
     * only allowed to have remote URLs (such as `https://example.com`) if they
     * use a known protocol.
     *
     * For example:
     *
     * ```js
     * protocols: {
     * cite: ['http', 'https'],
     * // …
     * src: ['http', 'https']
     * }
     * ```
     */
    protocols?: Record<string, Array<string> | null | undefined> | null | undefined;
    /**
     * Map of tag names to required property names with a default value
     * (default: `defaultSchema.required`).
     *
     * This defines properties that must be set.
     * If a field does not exist (after the element was made safe), these will be
     * added with the given value.
     *
     * For example:
     *
     * ```js
     * required: {
     * input: {disabled: true, type: 'checkbox'}
     * }
     * ```
     *
     * > 👉 **Note**: properties are first checked based on `schema.attributes`,
     * > then on `schema.required`.
     * > That means properties could be removed by `attributes` and then added
     * > again with `required`.
     */
    required?: Record<string, Record<string, Properties[keyof Properties]>> | null | undefined;
    /**
     * List of tag names to strip from the tree (default: `defaultSchema.strip`).
     *
     * By default, unsafe elements (those not in `schema.tagNames`) are replaced
     * by what they contain.
     * This option can drop their contents.
     *
     * For example:
     *
     * ```js
     * strip: ['script']
     * ```
     */
    strip?: Array<string> | null | undefined;
    /**
     * List of allowed tag names (default: `defaultSchema.tagNames`).
     *
     * For example:
     *
     * ```js
     * tagNames: [
     * 'a',
     * 'b',
     * // …
     * 'ul',
     * 'var'
     * ]
     * ```
     */
    tagNames?: Array<string> | null | undefined;
};
/**
 * Info passed around.
 */
export type State = {
    /**
     *   Schema.
     */
    schema: Readonly<Schema>;
    /**
     *   Tag names of ancestors.
     */
    stack: Array<string>;
};
import type { Nodes } from 'hast';
import type { Properties } from 'hast';
//# sourceMappingURL=index.d.ts.map