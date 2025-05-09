import { ViewPlugin, DecorationSet, ViewUpdate } from '@codemirror/view';
import { Extension, Text } from '@codemirror/state';
import { Tree } from '@lezer/common';

interface PickerState {
    from: number;
    to: number;
    alpha: string;
    colorType: ColorType;
}
interface WidgetOptions extends PickerState {
    color: string;
}
type ColorData = Omit<WidgetOptions, 'from' | 'to'>;
declare enum ColorType {
    rgb = "RGB",
    hex = "HEX",
    named = "NAMED",
    hsl = "HSL"
}
declare function discoverColorsInCSS(syntaxTree: Tree, from: number, to: number, typeName: string, doc: Text, language?: string): WidgetOptions | Array<WidgetOptions> | null;
declare function parseCallExpression(callExp: string): ColorData | null;
declare function parseColorLiteral(colorLiteral: string): ColorData | null;
declare function parseNamedColor(colorName: string): ColorData | null;
declare const wrapperClassName = "cm-css-color-picker-wrapper";
declare const colorPickerTheme: Extension;
interface IFactoryOptions {
    discoverColors: typeof discoverColorsInCSS;
}
declare const makeColorPicker: (options: IFactoryOptions) => ViewPlugin<{
    decorations: DecorationSet;
    update(update: ViewUpdate): void;
}>;
declare const colorPicker: Extension;

export { ColorData, ColorType, WidgetOptions, colorPicker, colorPickerTheme, makeColorPicker, parseCallExpression, parseColorLiteral, parseNamedColor, wrapperClassName };
