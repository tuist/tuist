/**
 * @import {Nodes, RootContent, Root} from 'hast'
 * @import {BuildVisitor} from 'unist-util-visit-parents'
 * @import {Options, State} from './types.js'
 */

import {embedded} from 'hast-util-embedded'
import {minifyWhitespace} from 'hast-util-minify-whitespace'
import {phrasing} from 'hast-util-phrasing'
import {whitespace} from 'hast-util-whitespace'
import {whitespaceSensitiveTagNames} from 'html-whitespace-sensitive-tag-names'
import {SKIP, visitParents} from 'unist-util-visit-parents'

/** @type {Options} */
const emptyOptions = {}

/**
 * Format whitespace in HTML.
 *
 * @param {Root} tree
 *   Tree.
 * @param {Options | null | undefined} [options]
 *   Configuration (optional).
 * @returns {undefined}
 *   Nothing.
 */
export function format(tree, options) {
  const settings = options || emptyOptions

  /** @type {State} */
  const state = {
    blanks: settings.blanks || [],
    head: false,
    indentInitial: settings.indentInitial !== false,
    indent:
      typeof settings.indent === 'number'
        ? ' '.repeat(settings.indent)
        : typeof settings.indent === 'string'
          ? settings.indent
          : '  '
  }

  minifyWhitespace(tree, {newlines: true})

  visitParents(tree, visitor)

  /**
   * @type {BuildVisitor<Root>}
   */
  function visitor(node, parents) {
    if (!('children' in node)) {
      return
    }

    if (node.type === 'element' && node.tagName === 'head') {
      state.head = true
    }

    if (state.head && node.type === 'element' && node.tagName === 'body') {
      state.head = false
    }

    if (
      node.type === 'element' &&
      whitespaceSensitiveTagNames.includes(node.tagName)
    ) {
      return SKIP
    }

    // Don’t indent content of whitespace-sensitive nodes / inlines.
    if (node.children.length === 0 || !padding(state, node)) {
      return
    }

    let level = parents.length

    if (!state.indentInitial) {
      level--
    }

    let eol = false

    // Indent newlines in `text`.
    for (const child of node.children) {
      if (child.type === 'comment' || child.type === 'text') {
        if (child.value.includes('\n')) {
          eol = true
        }

        child.value = child.value.replace(
          / *\n/g,
          '$&' + state.indent.repeat(level)
        )
      }
    }

    /** @type {Array<RootContent>} */
    const result = []
    /** @type {RootContent | undefined} */
    let previous

    for (const child of node.children) {
      if (padding(state, child) || (eol && !previous)) {
        addBreak(result, level, child)
        eol = true
      }

      previous = child
      result.push(child)
    }

    if (previous && (eol || padding(state, previous))) {
      // Ignore trailing whitespace (if that already existed), as we’ll add
      // properly indented whitespace.
      if (whitespace(previous)) {
        result.pop()
        previous = result[result.length - 1]
      }

      addBreak(result, level - 1)
    }

    node.children = result
  }

  /**
   * @param {Array<RootContent>} list
   *   Nodes.
   * @param {number} level
   *   Indentation level.
   * @param {RootContent | undefined} [next]
   *   Next node.
   * @returns {undefined}
   *   Nothing.
   */
  function addBreak(list, level, next) {
    const tail = list[list.length - 1]
    const previous = tail && whitespace(tail) ? list[list.length - 2] : tail
    const replace =
      (blank(state, previous) && blank(state, next) ? '\n\n' : '\n') +
      state.indent.repeat(Math.max(level, 0))

    if (tail && tail.type === 'text') {
      tail.value = whitespace(tail) ? replace : tail.value + replace
    } else {
      list.push({type: 'text', value: replace})
    }
  }
}

/**
 * @param {State} state
 *   Info passed around.
 * @param {Nodes | undefined} node
 *   Node.
 * @returns {boolean}
 *   Whether `node` is a blank.
 */
function blank(state, node) {
  return Boolean(
    node &&
      node.type === 'element' &&
      state.blanks.length > 0 &&
      state.blanks.includes(node.tagName)
  )
}

/**
 * @param {State} state
 *   Info passed around.
 * @param {Nodes} node
 *   Node.
 * @returns {boolean}
 *   Whether `node` should be padded.
 */
function padding(state, node) {
  return (
    node.type === 'root' ||
    (node.type === 'element'
      ? state.head ||
        node.tagName === 'script' ||
        embedded(node) ||
        !phrasing(node)
      : false)
  )
}
