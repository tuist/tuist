import { tags } from '@lezer/highlight';
import { createCodeMirrorTheme } from './createCodeMirrorTheme.js';

const customTheme = createCodeMirrorTheme({
    theme: 'light',
    settings: {
        background: 'var(--scalar-background-2)',
        foreground: 'var(--scalar-color-1)',
        caret: 'var(--scalar-color-1)',
        // Selection likely needs a hardcoded color due to it not accepting variables
        selectionMatch: '#e3dcce',
        gutterBackground: 'var(--scalar-background-2)',
        gutterForeground: 'var(--scalar-color-3)',
        gutterBorder: 'transparent',
        lineHighlight: 'var(--scalar-background-3)',
        fontFamily: 'var(--scalar-font-code)',
    },
    styles: [
        {
            tag: [tags.standard(tags.tagName), tags.tagName],
            color: 'var(--scalar-color-purple)',
        },
        {
            tag: [tags.comment],
            color: 'var(--scalar-color-3)',
        },
        {
            tag: [tags.className],
            color: 'var(--scalar-color-orange)',
        },
        {
            tag: [tags.variableName, tags.propertyName, tags.attributeName],
            color: 'var(--scalar-color-1)',
        },
        {
            tag: [tags.operator],
            color: 'var(--scalar-color-2)',
        },
        {
            tag: [tags.keyword, tags.typeName, tags.typeOperator],
            color: 'var(--scalar-color-green)',
        },
        {
            tag: [tags.string],
            color: 'var(--scalar-color-blue)',
        },
        {
            tag: [tags.bracket, tags.regexp, tags.meta],
            color: 'var(--scalar-color-3)',
        },
        {
            tag: [tags.number],
            color: 'var(--scalar-color-orange)',
        },
        {
            tag: [tags.name, tags.quote],
            color: 'var(--scalar-color-3)',
        },
        {
            tag: [tags.heading],
            color: 'var(--scalar-color-3)',
            fontWeight: 'bold',
        },
        {
            tag: [tags.emphasis],
            color: 'var(--scalar-color-3)',
            fontStyle: 'italic',
        },
        {
            tag: [tags.deleted],
            color: 'var(--scalar-color-3)',
            backgroundColor: 'transparent',
        },
        {
            tag: [tags.atom, tags.bool, tags.special(tags.variableName)],
            color: 'var(--scalar-color-3)',
        },
        {
            tag: [tags.url, tags.escape, tags.regexp, tags.link],
            color: 'var(--scalar-color-1)',
        },
        { tag: tags.link, textDecoration: 'underline' },
        { tag: tags.strikethrough, textDecoration: 'line-through' },
        {
            tag: tags.invalid,
            color: 'var(--scalar-color-3)',
        },
    ],
});

export { customTheme };
