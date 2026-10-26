# Vendored Atlas browser assets

`highlight.js` is a generated, locally bundled **highlight.js 11.11.1** subset: core, JSON and JavaScript only. It exports `highlight(source, language)` and does not scan the DOM, fetch languages, install globals, or execute submitted code. `highlight.LICENSE` contains its BSD-3-Clause license; the generated bundle's legal banner includes the complete license so it survives production asset minification.

Source: `https://registry.npmjs.org/highlight.js/-/highlight.js-11.11.1.tgz`.
SHA-256: `fbc9443263e976583bd5640e550b77f84d8d7e19fc8408dfe53776a5bae7ed39`.

To regenerate, download and verify that archive in a temporary directory and extract its `package/` contents. Create an adjacent ES module importing the default exports from `./package/lib/core.js`, `./package/lib/languages/json.js` and `./package/lib/languages/javascript.js`; register the two languages, then export `highlight(source, language)` returning `hljs.highlight(source, {language, ignoreIllegals: true}).value`. Bundle that entry with Atlas's pinned esbuild binary (`--bundle --minify --format=esm --target=es2022 --legal-comments=inline`). Supply a `/*! ... */` banner naming the version/subset and containing the full upstream license. Copy the upstream license alongside the generated module. Do not add unrelated languages or a second package-management/build path just to refresh this small subset.

The consuming `CodeEditor` hook bounds both source bytes and generated markup. Only escaped highlighter output becomes DOM; tokens use `data-token` attributes and CSS controls their palette. Ordinary textarea input, selection, undo, form submission and fallback behavior stay browser-native. See the code-editor tests under `../js/hooks/`.
