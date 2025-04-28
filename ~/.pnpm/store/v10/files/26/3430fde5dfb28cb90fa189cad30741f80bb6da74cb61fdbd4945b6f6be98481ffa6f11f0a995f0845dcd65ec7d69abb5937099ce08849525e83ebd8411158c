/**
 * @typedef {import('hast').Root} Root
 * @typedef {import('hast-util-sanitize').Schema} Schema
 */

import {sanitize} from 'hast-util-sanitize'

/**
 * Sanitize HTML.
 *
 * @param {Schema | null | undefined} [options]
 *   Configuration (optional).
 * @returns
 *   Transform.
 */
export default function rehypeSanitize(options) {
  /**
   * @param {Root} tree
   *   Tree.
   * @returns {Root}
   *   New tree.
   */
  return function (tree) {
    // Assume root in -> root out.
    const result = /** @type {Root} */ (sanitize(tree, options))
    return result
  }
}
