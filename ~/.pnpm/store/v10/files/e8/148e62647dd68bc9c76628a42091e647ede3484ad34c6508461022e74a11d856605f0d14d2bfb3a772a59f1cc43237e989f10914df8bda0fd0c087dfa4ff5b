/**
 * @import {Options} from 'hast-util-format'
 * @import {Root} from 'hast'
 */

import {format} from 'hast-util-format'

/**
 * Format whitespace in HTML.
 *
 * @param {Options | null | undefined} [options]
 *   Configuration (optional).
 * @returns
 *   Transform.
 */
export default function rehypeFormat(options) {
  /**
   * Transform.
   *
   * @param {Root} tree
   *   Tree.
   * @returns {undefined}
   *   Nothing.
   */
  return function (tree) {
    format(tree, options)
  }
}
