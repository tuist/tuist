/**
 * This file is copied from @uiw/codemirror-themes.
 * We’ve had issues with the import (something to do with CJS/ESM).
 *
 * @see https://github.com/uiwjs/react-codemirror
 * @see https://github.com/scalar/scalar/issues/4222
 */
import { type TagStyle } from '@codemirror/language';
import type { Extension } from '@codemirror/state';
import type { StyleSpec } from 'style-mod';
export type CreateThemeOptions = {
    /**
     * Theme inheritance. Determines which styles CodeMirror will apply by default.
     */
    theme: Theme;
    /**
     * Settings to customize the look of the editor, like background, gutter, selection and others.
     */
    settings: Settings;
    /** Syntax highlighting styles. */
    styles: TagStyle[];
};
type Theme = 'light' | 'dark';
export type Settings = {
    /** Editor background color. */
    background?: string;
    /** Editor background image. */
    backgroundImage?: string;
    /** Default text color. */
    foreground?: string;
    /** Caret color. */
    caret?: string;
    /** Selection background. */
    selection?: string;
    /** Selection match background. */
    selectionMatch?: string;
    /** Background of highlighted lines. */
    lineHighlight?: string;
    /** Gutter background. */
    gutterBackground?: string;
    /** Text color inside gutter. */
    gutterForeground?: string;
    /** Text active color inside gutter. */
    gutterActiveForeground?: string;
    /** Gutter right border color. */
    gutterBorder?: string;
    /** set editor font */
    fontFamily?: string;
    /** set editor font size */
    fontSize?: StyleSpec['fontSize'];
};
/**
 * Creates a CodeMirror theme from a set of options.
 */
export declare const createCodeMirrorTheme: ({ theme, settings, styles }: CreateThemeOptions) => Extension;
export {};
//# sourceMappingURL=createCodeMirrorTheme.d.ts.map