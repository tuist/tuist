/**
 * @import {Nodes} from 'hast'
 */

const list = new Set(['pingback', 'prefetch', 'stylesheet'])

/**
 * Checks whether a node is a “body OK” link.
 *
 * @param {Nodes} node
 *   Node to check.
 * @returns {boolean}
 *   Whether `node` is a “body OK” link.
 */
export function isBodyOkLink(node) {
  if (node.type !== 'element' || node.tagName !== 'link') {
    return false
  }

  if (node.properties.itemProp) {
    return true
  }

  const value = node.properties.rel
  let index = -1

  if (!Array.isArray(value) || value.length === 0) {
    return false
  }

  while (++index < value.length) {
    if (!list.has(String(value[index]))) {
      return false
    }
  }

  return true
}
