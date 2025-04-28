# CodeMirror Color Picker

<span><a href="https://replit.com/@util/Codemirror-CSS-color-picker" title="Run on Replit badge"><img src="https://replit.com/badge/github/replit/Codemirror-CSS-color-picker" alt="Run on Replit badge" /></a></span>
<span><a href="https://www.npmjs.com/package/@replit/codemirror-css-color-picker" title="NPM version badge"><img src="https://img.shields.io/npm/v/@replit/codemirror-css-color-picker?color=blue" alt="NPM version badge" /></a></span>

A CodeMirror extension that adds a color picker input next to CSS color values.

![preview](https://replit.com/cdn-cgi/image/width=3840,quality=80/https://storage.googleapis.com/replit/images/1632627522442_46320608eaa3f0c58bebd5fe4a10efc2.gif)

### Usage

```ts
import { basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { css } from '@codemirror/lang-css';
import { colorPicker, wrapperClassName } from '@replit/codemirror-css-color-picker';

new EditorView({
  parent: document.querySelector('#editor'),
  state: EditorState.create({
    doc: '.wow {\n  color: #fff;\n}',
    extensions: [
      basicSetup,
      css(),
      colorPicker,
      EditorView.theme({
        [`.${wrapperClassName}`]: {
          outlineColor: 'transparent',
        },
      }),
    ],
  }),
});
```

### Todos

- Investigate solutions for alpha values. `input[type="color"]` doesn't support alpha values, we could show another number input next to it for the alpha value.
