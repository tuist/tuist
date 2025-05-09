import { HighlightStyle, syntaxHighlighting } from '@codemirror/language';
import { EditorView } from '@codemirror/view';

/**
 * This file is copied from @uiw/codemirror-themes.
 * We’ve had issues with the import (something to do with CJS/ESM).
 *
 * @see https://github.com/uiwjs/react-codemirror
 * @see https://github.com/scalar/scalar/issues/4222
 */
/**
 * Creates a CodeMirror theme from a set of options.
 */
const createCodeMirrorTheme = ({ theme, settings = {}, styles = [] }) => {
    const themeOptions = {
        '.cm-gutters': {},
    };
    const baseStyle = {};
    if (settings.background) {
        baseStyle.backgroundColor = settings.background;
    }
    if (settings.backgroundImage) {
        baseStyle.backgroundImage = settings.backgroundImage;
    }
    if (settings.foreground) {
        baseStyle.color = settings.foreground;
    }
    if (settings.fontSize) {
        baseStyle.fontSize = settings.fontSize;
    }
    if (settings.background || settings.foreground) {
        themeOptions['&'] = baseStyle;
    }
    if (settings.fontFamily) {
        themeOptions['&.cm-editor .cm-scroller'] = {
            fontFamily: settings.fontFamily,
        };
    }
    if (settings.gutterBackground) {
        themeOptions['.cm-gutters'].backgroundColor = settings.gutterBackground;
    }
    if (settings.gutterForeground) {
        themeOptions['.cm-gutters'].color = settings.gutterForeground;
    }
    if (settings.gutterBorder) {
        themeOptions['.cm-gutters'].borderRightColor = settings.gutterBorder;
    }
    if (settings.caret) {
        themeOptions['.cm-content'] = {
            caretColor: settings.caret,
        };
        themeOptions['.cm-cursor, .cm-dropCursor'] = {
            borderLeftColor: settings.caret,
        };
    }
    const activeLineGutterStyle = {};
    if (settings.gutterActiveForeground) {
        activeLineGutterStyle.color = settings.gutterActiveForeground;
    }
    if (settings.lineHighlight) {
        themeOptions['.cm-activeLine'] = {
            backgroundColor: settings.lineHighlight,
        };
        activeLineGutterStyle.backgroundColor = settings.lineHighlight;
    }
    themeOptions['.cm-activeLineGutter'] = activeLineGutterStyle;
    if (settings.selection) {
        themeOptions['&.cm-focused .cm-selectionBackground, & .cm-line::selection, & .cm-selectionLayer .cm-selectionBackground, .cm-content ::selection'] = {
            background: settings.selection + ' !important',
        };
    }
    if (settings.selectionMatch) {
        themeOptions['& .cm-selectionMatch'] = {
            backgroundColor: settings.selectionMatch,
        };
    }
    const themeExtension = EditorView.theme(themeOptions, {
        dark: theme === 'dark',
    });
    const highlightStyle = HighlightStyle.define(styles);
    const extension = [themeExtension, syntaxHighlighting(highlightStyle)];
    return extension;
};

export { createCodeMirrorTheme };
