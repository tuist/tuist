import { toRegExp } from 'oniguruma-to-es';
import { J as JavaScriptScanner } from './shared/engine-javascript.hzpS1_41.mjs';

function defaultJavaScriptRegexConstructor(pattern, options) {
  return toRegExp(
    pattern,
    {
      global: true,
      hasIndices: true,
      rules: {
        // Needed since TextMate grammars merge backrefs across patterns
        allowOrphanBackrefs: true,
        // Improves search performance for generated regexes
        asciiWordBoundaries: true,
        // Follow `vscode-oniguruma` which enables this Oniguruma option by default
        captureGroup: true,
        // Removing `\G` anchors in cases when they're not supported for emulation allows
        // supporting more grammars, but also allows some mismatches
        ignoreUnsupportedGAnchors: true
      },
      ...options
    }
  );
}
function createJavaScriptRegexEngine(options = {}) {
  const _options = Object.assign(
    {
      target: "auto",
      cache: /* @__PURE__ */ new Map()
    },
    options
  );
  _options.regexConstructor ||= (pattern) => defaultJavaScriptRegexConstructor(pattern, { target: _options.target });
  return {
    createScanner(patterns) {
      return new JavaScriptScanner(patterns, _options);
    },
    createString(s) {
      return {
        content: s
      };
    }
  };
}

export { createJavaScriptRegexEngine, defaultJavaScriptRegexConstructor };
