/*
 Language: cURL
 Category: scripting
 Author: John Foster <jfoster@esri.com>
 Description: Syntax highlighting for cURL commands.
*/

module.exports = function (hljs) {
  const QUOTE_STRING = {
    className: 'string',
    begin: /"/, end: /"/,
    contains: [
      hljs.BACKSLASH_ESCAPE,
      {
        className: 'variable',
        begin: /\$\(/, end: /\)/,
        contains: [hljs.BACKSLASH_ESCAPE]
      }
    ],
    relevance: 0
  };
  const OPTION_REQUEST = {
    className: 'literal',
    begin: /(--request|-X)\s/,
    contains: [
      {
        className: 'symbol',
        begin: /(get|post|delete|options|head|put|patch|trace|connect)/,
        end: /\s/,
        returnEnd: true
      }
    ],
    returnEnd: true,
    relevance: 10
  };
  const OPTION = {
    className: 'literal',
    begin: /--/, end: /[\s"]/,
    returnEnd: true,
    relevance: 0
  };
  const OPTION_SINGLE = {
    className: 'literal',
    begin: /-\w/, end: /[\s"]/,
    returnEnd: true,
    relevance: 0
  };
  const ESCAPED_QUOTE = {
    className: 'string',
    begin: /\\"/,
    relevance: 0
  };
  const APOS_STRING = {
    className: 'string',
    begin: /'/, end: /'/,
    relevance: 0
  };
  const NUMBER = {
    className: 'number',
    variants: [
      { begin: hljs.C_NUMBER_RE }
    ],
    relevance: 0
  };
  // to consume paths to prevent keyword matches inside them
  const PATH_MODE = {
    match: /(\/[a-z._-]+)+/
  };
  
  return {
    name: "curl",
    aliases: ["curl"],
    keywords: "curl",
    case_insensitive: true,
    contains: [
      OPTION_REQUEST,
      OPTION,
      OPTION_SINGLE,
      QUOTE_STRING,
      ESCAPED_QUOTE,
      APOS_STRING,
      hljs.APOS_STRING_MODE,
      hljs.QUOTE_STRING_MODE,
      NUMBER,
      PATH_MODE
    ]
  };
}
