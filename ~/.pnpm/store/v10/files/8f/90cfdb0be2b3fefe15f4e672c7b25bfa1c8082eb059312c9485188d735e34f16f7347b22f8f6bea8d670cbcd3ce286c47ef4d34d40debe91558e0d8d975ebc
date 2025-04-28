import {convertElement} from 'hast-util-is-element'

/**
 * Check if a node is a *embedded content*.
 *
 * @param value
 *   Thing to check (typically `Node`).
 * @returns
 *   Whether `value` is an element considered embedded content.
 *
 *   The elements `audio`, `canvas`, `embed`, `iframe`, `img`, `math`,
 *   `object`, `picture`, `svg`, and `video` are embedded content.
 */
export const embedded = convertElement(
  /**
   * @param element
   * @returns {element is {tagName: 'audio' | 'canvas' | 'embed' | 'iframe' | 'img' | 'math' | 'object' | 'picture' | 'svg' | 'video'}}
   */
  function (element) {
    return (
      element.tagName === 'audio' ||
      element.tagName === 'canvas' ||
      element.tagName === 'embed' ||
      element.tagName === 'iframe' ||
      element.tagName === 'img' ||
      element.tagName === 'math' ||
      element.tagName === 'object' ||
      element.tagName === 'picture' ||
      element.tagName === 'svg' ||
      element.tagName === 'video'
    )
  }
)
