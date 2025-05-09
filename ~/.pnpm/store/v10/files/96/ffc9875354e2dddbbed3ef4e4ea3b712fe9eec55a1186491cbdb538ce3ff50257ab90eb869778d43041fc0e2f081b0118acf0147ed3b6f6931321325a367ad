import type { Root } from 'hast';
import { createLowlight, type LanguageFn } from 'lowlight';
import type { VFile } from 'vfile';
type HighlightOptions = {
    /** Optional existing lowlight instance to use */
    lowlight?: ReturnType<typeof createLowlight> | undefined;
    /** Register more aliases (optional); passed to `lowlight.registerAlias` */
    aliases?: Readonly<Record<string, ReadonlyArray<string> | string>> | null | undefined;
    /** Register languages (default: `common`) passed to `lowlight.register` */
    languages?: Readonly<Record<string, LanguageFn>> | null | undefined;
    /** List of language names to not highlight (optional). Note: you can also add `no-highlight` classes. */
    plainText?: ReadonlyArray<string> | null | undefined;
    /** Class prefix (default: `'hljs-'`) */
    prefix?: string | null | undefined;
    /** Names of languages to check when detecting (default: all registered languages) */
    subset?: ReadonlyArray<string> | null | undefined;
    /** Option to autodetect languages */
    detect?: boolean;
};
/**
 * Lowlight syntax highlighting plugin for rehype pipelines
 *
 * Derived from: @url https://github.com/rehypejs/rehype-highlight/blob/main/lib/index.js
 */
export declare function rehypeHighlight(options?: Readonly<HighlightOptions> | null | undefined): (tree: Root, file: VFile) => void;
export {};
//# sourceMappingURL=rehype-highlight.d.ts.map