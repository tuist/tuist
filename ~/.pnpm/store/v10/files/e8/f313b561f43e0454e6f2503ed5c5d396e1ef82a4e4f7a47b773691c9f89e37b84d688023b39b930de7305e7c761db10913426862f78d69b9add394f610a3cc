import { MatchDecorator, Decoration, ViewPlugin, EditorView } from '@codemirror/view';

const variableHighlighterDecoration = new MatchDecorator({
    regexp: /(\{[^}]+\})/g,
    decoration: () => Decoration.mark({
        attributes: {
            class: 'api-client-url-variable',
        },
    }),
});
const variables = () => ViewPlugin.fromClass(class {
    variables;
    constructor(view) {
        this.variables = variableHighlighterDecoration.createDeco(view);
    }
    update(update) {
        this.variables = variableHighlighterDecoration.updateDeco(update, this.variables);
    }
}, {
    decorations: (instance) => instance.variables,
    provide: (plugin) => EditorView.atomicRanges.of((view) => view.plugin(plugin)?.variables || Decoration.none),
});

export { variables };
