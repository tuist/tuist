import { basicSetup } from 'codemirror';
import { css } from '@codemirror/lang-css';
import { html } from '@codemirror/lang-html';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { colorPicker, wrapperClassName } from '../src/';

const cssDoc = `
.wow {
  font-family: Helvetica Neue;
  font-size: 17px;
  color: #ff0000;
  border-color: rgb(0, 255, 0%);
  background-color: #00f;
}

#alpha {
  color: #FF00FFAA;
  border-color: rgb(255, 50%, 64, 0.5);
  border-color: rgba(255, 50%, 64, 0.5);
}

.hex4 {
  color: #ABCD;
}

.named {
  color: red;
  background-color: blue;
  border-top-color: aquamarine;
  border-left-color: mediumaquamarine;
  border-right-color: lightcoral;
  border-bottom-color: snow;
}

#hue {
  color: hsl(0, 100%, 50%);
}
`;

const htmlDoc = `
<html>
  <head>
    <style>
      ${cssDoc}
    </style>
  </head>
  <body>

  <body>
    <div
      style="
        font-family: Helvetica Neue;
        font-size: 17px;
        color: #ff0000;
        border-color: rgb(0, 255, 0%);
        background-color: #00f;
      "
    >
      wow
    </div>
    <div
      style="
        color: #ff00ffaa;
        border-color: rgb(255, 50%, 64, 0.5);
        border-color: rgba(255, 50%, 64, 0.5);
      "
    >
      alpha
    </div>
    <div style="color: #abcd">hex4</div>
    <div
      style="
        color: red;
        background-color: blue;
        border-top-color: aquamarine;
        border-left-color: mediumaquamarine;
        border-right-color: lightcoral;
        border-bottom-color: snow;
      "
    >
      named
    </div>
    <div style="color: hsl(0, 100%, 50%)">hue</div>
  </body>
</html>
`;

const cssParent = document.querySelector('#editor-css');
const htmlParent = document.querySelector('#editor-html');

if (!cssParent || !htmlParent) {
  throw new Error('Could not find #editor-css or #editor-html');
}

new EditorView({
  state: EditorState.create({
    doc: cssDoc,
    extensions: [
      colorPicker,
      basicSetup,
      css(),
      EditorView.theme({
        [`.${wrapperClassName}`]: {
          outlineColor: '#000',
        },
      }),
    ],
  }),
  parent: cssParent,
});

new EditorView({
  state: EditorState.create({
    doc: htmlDoc,
    extensions: [
      colorPicker,
      basicSetup,
      html(),
      EditorView.theme({
        [`.${wrapperClassName}`]: {
          outlineColor: '#000',
        },
      }),
    ],
  }),
  parent: cssParent,
});
