/**
 * @import {Schema} from 'hast-util-sanitize'
 */

// Couple of ARIA attributes allowed in several, but not all, places.
const aria = ['ariaDescribedBy', 'ariaLabel', 'ariaLabelledBy']

/**
 * Default schema.
 *
 * Follows GitHub style sanitation.
 *
 * @type {Schema}
 */
export const defaultSchema = {
  ancestors: {
    tbody: ['table'],
    td: ['table'],
    th: ['table'],
    thead: ['table'],
    tfoot: ['table'],
    tr: ['table']
  },
  attributes: {
    a: [
      ...aria,
      // Note: these 3 are used by GFM footnotes, they do work on all links.
      'dataFootnoteBackref',
      'dataFootnoteRef',
      ['className', 'data-footnote-backref'],
      'href'
    ],
    blockquote: ['cite'],
    // Note: this class is not normally allowed by GH, when manually writing
    // `code` as HTML in markdown, they adds it some other way.
    // We can’t do that, so we have to allow it.
    code: [['className', /^language-./]],
    del: ['cite'],
    div: ['itemScope', 'itemType'],
    dl: [...aria],
    // Note: this is used by GFM footnotes.
    h2: [['className', 'sr-only']],
    img: [...aria, 'longDesc', 'src'],
    // Note: `input` is not normally allowed by GH, when manually writing
    // it in markdown, they add it from tasklists some other way.
    // We can’t do that, so we have to allow it.
    input: [
      ['disabled', true],
      ['type', 'checkbox']
    ],
    ins: ['cite'],
    // Note: this class is not normally allowed by GH, when manually writing
    // `li` as HTML in markdown, they adds it some other way.
    // We can’t do that, so we have to allow it.
    li: [['className', 'task-list-item']],
    // Note: this class is not normally allowed by GH, when manually writing
    // `ol` as HTML in markdown, they adds it some other way.
    // We can’t do that, so we have to allow it.
    ol: [...aria, ['className', 'contains-task-list']],
    q: ['cite'],
    section: ['dataFootnotes', ['className', 'footnotes']],
    source: ['srcSet'],
    summary: [...aria],
    table: [...aria],
    // Note: this class is not normally allowed by GH, when manually writing
    // `ol` as HTML in markdown, they adds it some other way.
    // We can’t do that, so we have to allow it.
    ul: [...aria, ['className', 'contains-task-list']],
    '*': [
      'abbr',
      'accept',
      'acceptCharset',
      'accessKey',
      'action',
      'align',
      'alt',
      'axis',
      'border',
      'cellPadding',
      'cellSpacing',
      'char',
      'charOff',
      'charSet',
      'checked',
      'clear',
      'colSpan',
      'color',
      'cols',
      'compact',
      'coords',
      'dateTime',
      'dir',
      // Note: `disabled` is technically allowed on all elements by GH.
      // But it is useless on everything except `input`.
      // Because `input`s are normally not allowed, but we allow them for
      // checkboxes due to tasklists, we allow `disabled` only there.
      'encType',
      'frame',
      'hSpace',
      'headers',
      'height',
      'hrefLang',
      'htmlFor',
      'id',
      'isMap',
      'itemProp',
      'label',
      'lang',
      'maxLength',
      'media',
      'method',
      'multiple',
      'name',
      'noHref',
      'noShade',
      'noWrap',
      'open',
      'prompt',
      'readOnly',
      'rev',
      'rowSpan',
      'rows',
      'rules',
      'scope',
      'selected',
      'shape',
      'size',
      'span',
      'start',
      'summary',
      'tabIndex',
      'title',
      'useMap',
      'vAlign',
      'value',
      'width'
    ]
  },
  clobber: ['ariaDescribedBy', 'ariaLabelledBy', 'id', 'name'],
  clobberPrefix: 'user-content-',
  protocols: {
    cite: ['http', 'https'],
    href: ['http', 'https', 'irc', 'ircs', 'mailto', 'xmpp'],
    longDesc: ['http', 'https'],
    src: ['http', 'https']
  },
  required: {
    input: {disabled: true, type: 'checkbox'}
  },
  strip: ['script'],
  tagNames: [
    'a',
    'b',
    'blockquote',
    'br',
    'code',
    'dd',
    'del',
    'details',
    'div',
    'dl',
    'dt',
    'em',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'i',
    'img',
    // Note: `input` is not normally allowed by GH, when manually writing
    // it in markdown, they add it from tasklists some other way.
    // We can’t do that, so we have to allow it.
    'input',
    'ins',
    'kbd',
    'li',
    'ol',
    'p',
    'picture',
    'pre',
    'q',
    'rp',
    'rt',
    'ruby',
    's',
    'samp',
    'section',
    'source',
    'span',
    'strike',
    'strong',
    'sub',
    'summary',
    'sup',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'tt',
    'ul',
    'var'
  ]
}
