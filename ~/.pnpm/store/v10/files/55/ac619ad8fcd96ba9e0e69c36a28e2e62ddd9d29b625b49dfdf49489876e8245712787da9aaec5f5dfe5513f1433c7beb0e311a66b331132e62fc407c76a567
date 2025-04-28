/**
 * @import {Nodes, Parents, Text} from 'hast'
 */

/**
 * @callback Collapse
 *   Collapse a string.
 * @param {string} value
 *   Value to collapse.
 * @returns {string}
 *   Collapsed value.
 *
 * @typedef Options
 *   Configuration.
 * @property {boolean | null | undefined} [newlines=false]
 *   Collapse whitespace containing newlines to `'\n'` instead of `' '`
 *   (default: `false`); the default is to collapse to a single space.
 *
 * @typedef Result
 *   Result.
 * @property {boolean} remove
 *   Whether to remove.
 * @property {boolean} ignore
 *   Whether to ignore.
 * @property {boolean} stripAtStart
 *   Whether to strip at the start.
 *
 * @typedef State
 *   Info passed around.
 * @property {Collapse} collapse
 *   Collapse.
 * @property {Whitespace} whitespace
 *   Current whitespace.
 * @property {boolean | undefined} [before]
 *   Whether there is a break before (default: `false`).
 * @property {boolean | undefined} [after]
 *   Whether there is a break after (default: `false`).
 *
 * @typedef {'normal' | 'nowrap' | 'pre' | 'pre-wrap'} Whitespace
 *   Whitespace setting.
 */

import {embedded} from 'hast-util-embedded'
import {isElement} from 'hast-util-is-element'
import {whitespace} from 'hast-util-whitespace'
import {convert} from 'unist-util-is'
import {blocks} from './block.js'
import {content as contents} from './content.js'
import {skippable as skippables} from './skippable.js'

/** @type {Options} */
const emptyOptions = {}
const ignorableNode = convert(['comment', 'doctype'])

/**
 * Minify whitespace.
 *
 * @param {Nodes} tree
 *   Tree.
 * @param {Options | null | undefined} [options]
 *   Configuration (optional).
 * @returns {undefined}
 *   Nothing.
 */
export function minifyWhitespace(tree, options) {
  const settings = options || emptyOptions

  minify(tree, {
    collapse: collapseFactory(
      settings.newlines ? replaceNewlines : replaceWhitespace
    ),
    whitespace: 'normal'
  })
}

/**
 * @param {Nodes} node
 *   Node.
 * @param {State} state
 *   Info passed around.
 * @returns {Result}
 *   Result.
 */
function minify(node, state) {
  if ('children' in node) {
    const settings = {...state}

    if (node.type === 'root' || blocklike(node)) {
      settings.before = true
      settings.after = true
    }

    settings.whitespace = inferWhiteSpace(node, state)

    return all(node, settings)
  }

  if (node.type === 'text') {
    if (state.whitespace === 'normal') {
      return minifyText(node, state)
    }

    // Naïve collapse, but no trimming:
    if (state.whitespace === 'nowrap') {
      node.value = state.collapse(node.value)
    }

    // The `pre-wrap` or `pre` whitespace settings are neither collapsed nor
    // trimmed.
  }

  return {ignore: ignorableNode(node), stripAtStart: false, remove: false}
}

/**
 * @param {Text} node
 *   Node.
 * @param {State} state
 *   Info passed around.
 * @returns {Result}
 *   Result.
 */
function minifyText(node, state) {
  const value = state.collapse(node.value)
  const result = {ignore: false, stripAtStart: false, remove: false}
  let start = 0
  let end = value.length

  if (state.before && removable(value.charAt(0))) {
    start++
  }

  if (start !== end && removable(value.charAt(end - 1))) {
    if (state.after) {
      end--
    } else {
      result.stripAtStart = true
    }
  }

  if (start === end) {
    result.remove = true
  } else {
    node.value = value.slice(start, end)
  }

  return result
}

/**
 * @param {Parents} parent
 *   Node.
 * @param {State} state
 *   Info passed around.
 * @returns {Result}
 *   Result.
 */
function all(parent, state) {
  let before = state.before
  const after = state.after
  const children = parent.children
  let length = children.length
  let index = -1

  while (++index < length) {
    const result = minify(children[index], {
      ...state,
      after: collapsableAfter(children, index, after),
      before
    })

    if (result.remove) {
      children.splice(index, 1)
      index--
      length--
    } else if (!result.ignore) {
      before = result.stripAtStart
    }

    // If this element, such as a `<select>` or `<img>`, contributes content
    // somehow, allow whitespace again.
    if (content(children[index])) {
      before = false
    }
  }

  return {ignore: false, stripAtStart: Boolean(before || after), remove: false}
}

/**
 * @param {Array<Nodes>} nodes
 *   Nodes.
 * @param {number} index
 *   Index.
 * @param {boolean | undefined} [after]
 *   Whether there is a break after `nodes` (default: `false`).
 * @returns {boolean | undefined}
 *   Whether there is a break after the node at `index`.
 */
function collapsableAfter(nodes, index, after) {
  while (++index < nodes.length) {
    const node = nodes[index]
    let result = inferBoundary(node)

    if (result === undefined && 'children' in node && !skippable(node)) {
      result = collapsableAfter(node.children, -1)
    }

    if (typeof result === 'boolean') {
      return result
    }
  }

  return after
}

/**
 * Infer two types of boundaries:
 *
 * 1. `true` — boundary for which whitespace around it does not contribute
 *    anything
 * 2. `false` — boundary for which whitespace around it *does* contribute
 *
 * No result (`undefined`) is returned if it is unknown.
 *
 * @param {Nodes} node
 *   Node.
 * @returns {boolean | undefined}
 *   Boundary.
 */
function inferBoundary(node) {
  if (node.type === 'element') {
    if (content(node)) {
      return false
    }

    if (blocklike(node)) {
      return true
    }

    // Unknown: either depends on siblings if embedded or metadata, or on
    // children.
  } else if (node.type === 'text') {
    if (!whitespace(node)) {
      return false
    }
  } else if (!ignorableNode(node)) {
    return false
  }
}

/**
 * Infer whether a node is skippable.
 *
 * @param {Nodes} node
 *   Node.
 * @returns {boolean}
 *   Whether `node` is skippable.
 */
function content(node) {
  return embedded(node) || isElement(node, contents)
}

/**
 * See: <https://html.spec.whatwg.org/#the-css-user-agent-style-sheet-and-presentational-hints>
 *
 * @param {Nodes} node
 *   Node.
 * @returns {boolean}
 *   Whether `node` is block-like.
 */
function blocklike(node) {
  return isElement(node, blocks)
}

/**
 * @param {Parents} node
 *   Node.
 * @returns {boolean}
 *   Whether `node` is skippable.
 */
function skippable(node) {
  return (
    Boolean(node.type === 'element' && node.properties.hidden) ||
    ignorableNode(node) ||
    isElement(node, skippables)
  )
}

/**
 * @param {string} character
 *   Character.
 * @returns {boolean}
 *   Whether `character` is removable.
 */
function removable(character) {
  return character === ' ' || character === '\n'
}

/**
 * @type {Collapse}
 */
function replaceNewlines(value) {
  const match = /\r?\n|\r/.exec(value)
  return match ? match[0] : ' '
}

/**
 * @type {Collapse}
 */
function replaceWhitespace() {
  return ' '
}

/**
 * @param {Collapse} replace
 * @returns {Collapse}
 *   Collapse.
 */
function collapseFactory(replace) {
  return collapse

  /**
   * @type {Collapse}
   */
  function collapse(value) {
    return String(value).replace(/[\t\n\v\f\r ]+/g, replace)
  }
}

/**
 * We don’t need to support void elements here (so `nobr wbr` -> `normal` is
 * ignored).
 *
 * @param {Parents} node
 *   Node.
 * @param {State} state
 *   Info passed around.
 * @returns {Whitespace}
 *   Whitespace.
 */
function inferWhiteSpace(node, state) {
  if ('tagName' in node && node.properties) {
    switch (node.tagName) {
      // Whitespace in script/style, while not displayed by CSS as significant,
      // could have some meaning in JS/CSS, so we can’t touch them.
      case 'listing':
      case 'plaintext':
      case 'script':
      case 'style':
      case 'xmp': {
        return 'pre'
      }

      case 'nobr': {
        return 'nowrap'
      }

      case 'pre': {
        return node.properties.wrap ? 'pre-wrap' : 'pre'
      }

      case 'td':
      case 'th': {
        return node.properties.noWrap ? 'nowrap' : state.whitespace
      }

      case 'textarea': {
        return 'pre-wrap'
      }

      default:
    }
  }

  return state.whitespace
}
