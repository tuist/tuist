# highlightjs-curl

Support for using `highlight.js` to syntax highlight cURL commands. See https://highlightjs.org/ for more information about highlight.js. See https://curl.haxx.se/docs/manpage.html or in your shell use `curl --help` for more information about cURL.

## Installation

Include the `highlight.js` script package in your webpage or node app, load this module and register it with `hljs`.

This cURL module is not part of the standard distribution and must be loaded separately. The module name is `curl.min.js` or `curl`, depending on how you reference the module from your bundler code.

### Static website

Load the `curl` module after loading Highlight.js.  Use the minified version found in the `dist` directory.  This module is just a CDN build of the language, so it will register itself as the JavaScript is loaded.

```html
<script type="text/javascript" src="/path/to/highlight.min.js"></script>
<script type="text/javascript" src="/path/to/curl.min.js"></script>
<script type="text/javascript">
  hljs.highlightAll();
</script>
```

### Using directly from the UNPKG CDN

```html
<script type="text/javascript"
  src="https://unpkg.com/highlightjs-curl@1.3.0/dist/curl.min.js"></script>
```

- More info: <https://unpkg.com>

### With Node or another build system

If you're using Node / Webpack / Rollup / Browserify, etc, simply require the language module, then register it with Highlight.js.

```javascript
var hljs = require('highlight.js');
var hljsCurl = require('highlightjs-curl');

hljs.registerLanguage("curl", hljsCurl);
hljs.highlightAll();
```

## Usage

Once loaded, mark the code you want to highlight with the `language-curl` class:

```html
<pre><code class="language-curl">...</code></pre>
```

Without specifying the language, Highlight.js will attempt to auto-detect the grammar. Since this curl grammar is an extension of bash, it may detect bash or some other grammar instead. Therefore, always specify `curl` or `language-curl`.

For more information, follow instructions at [highlightjs.org](https://highlightjs.org/usage/) to learn how to include the library and CSS and other use cases. See [Getting started](https://github.com/highlightjs/highlight.js#getting-started) for different integration and module options.

## Contributing

[Contributions welcome](https://github.com/esri/contributing). Download this repo and install the dependencies:

```bash
npm install
```

Update `src/language/curl.js`. Be sure to update the test data `test/markup` and `test/detect` files to include a test for your changes, or create a new test in `spec/curl-spec.js`. Run the local test with

```bash
npm test
```

The tests must pass!

To build the distribution, follow instructions at [Highlight.js 3rd Party Quick Start](https://github.com/highlightjs/highlight.js/blob/master/extra/3RD_PARTY_QUICK_START.md).

Issue a pull request.

## License

Licensed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0) (the "License"); you may not use this file except in compliance with the License.
