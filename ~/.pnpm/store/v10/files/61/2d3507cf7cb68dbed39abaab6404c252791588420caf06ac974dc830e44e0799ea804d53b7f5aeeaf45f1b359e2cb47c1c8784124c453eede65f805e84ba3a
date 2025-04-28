import { type EnvVariables } from '../../libs/env-helpers';
import type { Environment } from '@scalar/oas-utils/entities/environment';
import type { Workspace } from '@scalar/oas-utils/entities/workspace';
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@scalar/use-codemirror';
/**
 * Styles the active environment variable pill
 */
export declare const pillPlugin: (props: {
    environment: Environment | undefined;
    envVariables: EnvVariables | undefined;
    workspace: Workspace | undefined;
    isReadOnly: boolean | undefined;
}) => ViewPlugin<{
    decorations: DecorationSet;
    update(update: ViewUpdate): void;
    buildDecorations(view: EditorView): import("@codemirror/state").RangeSet<Decoration>;
}>;
export declare const backspaceCommand: import("@codemirror/state").Extension;
//# sourceMappingURL=codeVariableWidget.d.ts.map