/**
 * Configuration.
 */
export interface Options {
  /**
   * List of tag names to join with a blank line (default: `[]`);
   * these tags,
   * when next to each other,
   * are joined by a blank line (`\n\n`);
   * for example,
   * when `['head', 'body']` is given,
   * a blank line is added between these two.
   */
  blanks?: Array<string> | null | undefined
  /**
   * Whether to indent the first level (default: `true`);
   * this is usually the `<html>`,
   * thus not indenting `head` and `body`.
   */
  indentInitial?: boolean | null | undefined
  /**
   * Indentation per level (default: `2`);
   * when `number`,
   * uses that amount of spaces; when `string`,
   * uses that per indentation level.
   */
  indent?: number | string | null | undefined
}

/**
 * State.
 */
export interface State {
  /**
   * List of tag names to join with a blank line.
   */
  blanks: Array<string>
  /**
   * Whether the node is in `head`.
   */
  head: boolean
  /**
   * Whether to indent the first level.
   */
  indentInitial: boolean
  /**
   * Indentation per level.
   */
  indent: string
}
