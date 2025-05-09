import { type Extension } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { type MaybeRefOrGetter, type Ref } from 'vue';
import type { CodeMirrorLanguage } from '../types';
type BaseParameters = {
    /** Element Ref to mount codemirror to */
    codeMirrorRef: Ref<HTMLDivElement | null>;
    /** List of optional extensions for the instance */
    extensions?: MaybeRefOrGetter<Extension[]>;
    /** Whether to load a theme.*/
    withoutTheme?: MaybeRefOrGetter<boolean | undefined>;
    /** Languages to support for syntax highlighting */
    language: MaybeRefOrGetter<CodeMirrorLanguage | undefined>;
    /** Class names to apply to the instance */
    classes?: MaybeRefOrGetter<string[] | undefined>;
    /** Put the editor into read-only mode */
    readOnly?: MaybeRefOrGetter<boolean | undefined>;
    /** Disable indent with tab */
    disableTabIndent?: MaybeRefOrGetter<boolean | undefined>;
    /** Option to show line numbers in the editor */
    lineNumbers?: MaybeRefOrGetter<boolean | undefined>;
    withVariables?: MaybeRefOrGetter<boolean | undefined>;
    forceFoldGutter?: MaybeRefOrGetter<boolean | undefined>;
    disableEnter?: MaybeRefOrGetter<boolean | undefined>;
    disableCloseBrackets?: MaybeRefOrGetter<boolean | undefined>;
    /** Option to lint and show error in the editor */
    lint?: MaybeRefOrGetter<boolean | undefined>;
    onBlur?: (v: string) => void;
    onFocus?: (v: string) => void;
    placeholder?: MaybeRefOrGetter<string | undefined>;
};
export type UseCodeMirrorParameters = (BaseParameters & {
    /** Prefill the content. Will be ignored when a provider is given. */
    content: MaybeRefOrGetter<string | undefined>;
    onChange?: (v: string) => void;
}) | (BaseParameters & {
    provider: MaybeRefOrGetter<Extension | null>;
    content?: MaybeRefOrGetter<string | undefined>;
    onChange?: (v: string) => void;
});
/** Reactive CodeMirror Integration */
export declare const useCodeMirror: (params: UseCodeMirrorParameters) => {
    setCodeMirrorContent: (content?: string) => void;
    codeMirror: Ref<EditorView | null>;
};
export {};
//# sourceMappingURL=useCodeMirror.d.ts.map