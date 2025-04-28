/**
 * hast utility to minify whitespace between elements.
 *
 * ## What is this?
 *
 * This package is a utility that can minify the whitespace between elements.
 *
 * ## When should I use this?
 *
 * You can use this package when you want to improve the size of HTML fragments.
 *
 * ## Use
 *
 * ```js
 * import {h} from 'hastscript'
 * import {minifyWhitespace} from 'hast-util-minify-whitespace'
 *
 * const tree = h('p', [
 *   '  ',
 *   h('strong', 'foo'),
 *   '  ',
 *   h('em', 'bar'),
 *   '  ',
 *   h('meta', {itemProp: true}),
 *   '  '
 * ])
 *
 * minifyWhitespace(tree)
 *
 * console.log(tree)
 * //=> h('p', [h('strong', 'foo'), ' ', h('em', 'bar'), h('meta', {itemProp: true})])
 * ```
 *
 * ## API
 *
 * ### `Options`
 *
 * Configuration (TypeScript type).
 *
 * ###### Fields
 *
 * * `newlines` (`boolean`, default: `false`)
 *   — collapse whitespace containing newlines to `'\n'` instead of `' '`
 *   (default: `false`);
 *   the default is to collapse to a single space
 *
 * ###### Returns
 *
 * Nothing (`undefined`).
 *
 * ### `minifywhitespace(tree[, options])`
 *
 * Minify whitespace.
 *
 * ###### Parameters
 *
 * * `tree` (`Node`) — tree
 * * `options` (`Options`, optional) — configuration
 *
 * ###### Returns
 *
 * Nothing (`undefined`).
 */

/**
 * @typedef {import('./lib/index.js').Options} Options
 */

export {minifyWhitespace} from './lib/index.js'
