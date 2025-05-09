import { EditorView, ViewPlugin, Decoration, WidgetType } from '@codemirror/view';
import { NodeProp } from '@lezer/common';
import { syntaxTree, language } from '@codemirror/language';

const namedColors = /*@__PURE__*/new Map([
    ['aliceblue', '#f0f8ff'],
    ['antiquewhite', '#faebd7'],
    ['aqua', '#00ffff'],
    ['aquamarine', '#7fffd4'],
    ['azure', '#f0ffff'],
    ['beige', '#f5f5dc'],
    ['bisque', '#ffe4c4'],
    ['black', '#000000'],
    ['blanchedalmond', '#ffebcd'],
    ['blue', '#0000ff'],
    ['blueviolet', '#8a2be2'],
    ['brown', '#a52a2a'],
    ['burlywood', '#deb887'],
    ['cadetblue', '#5f9ea0'],
    ['chartreuse', '#7fff00'],
    ['chocolate', '#d2691e'],
    ['coral', '#ff7f50'],
    ['cornflowerblue', '#6495ed'],
    ['cornsilk', '#fff8dc'],
    ['crimson', '#dc143c'],
    ['cyan', '#00ffff'],
    ['darkblue', '#00008b'],
    ['darkcyan', '#008b8b'],
    ['darkgoldenrod', '#b8860b'],
    ['darkgray', '#a9a9a9'],
    ['darkgreen', '#006400'],
    ['darkgrey', '#a9a9a9'],
    ['darkkhaki', '#bdb76b'],
    ['darkmagenta', '#8b008b'],
    ['darkolivegreen', '#556b2f'],
    ['darkorange', '#ff8c00'],
    ['darkorchid', '#9932cc'],
    ['darkred', '#8b0000'],
    ['darksalmon', '#e9967a'],
    ['darkseagreen', '#8fbc8f'],
    ['darkslateblue', '#483d8b'],
    ['darkslategray', '#2f4f4f'],
    ['darkslategrey', '#2f4f4f'],
    ['darkturquoise', '#00ced1'],
    ['darkviolet', '#9400d3'],
    ['deeppink', '#ff1493'],
    ['deepskyblue', '#00bfff'],
    ['dimgray', '#696969'],
    ['dimgrey', '#696969'],
    ['dodgerblue', '#1e90ff'],
    ['firebrick', '#b22222'],
    ['floralwhite', '#fffaf0'],
    ['forestgreen', '#228b22'],
    ['fuchsia', '#ff00ff'],
    ['gainsboro', '#dcdcdc'],
    ['ghostwhite', '#f8f8ff'],
    ['goldenrod', '#daa520'],
    ['gold', '#ffd700'],
    ['gray', '#808080'],
    ['green', '#008000'],
    ['greenyellow', '#adff2f'],
    ['grey', '#808080'],
    ['honeydew', '#f0fff0'],
    ['hotpink', '#ff69b4'],
    ['indianred', '#cd5c5c'],
    ['indigo', '#4b0082'],
    ['ivory', '#fffff0'],
    ['khaki', '#f0e68c'],
    ['lavenderblush', '#fff0f5'],
    ['lavender', '#e6e6fa'],
    ['lawngreen', '#7cfc00'],
    ['lemonchiffon', '#fffacd'],
    ['lightblue', '#add8e6'],
    ['lightcoral', '#f08080'],
    ['lightcyan', '#e0ffff'],
    ['lightgoldenrodyellow', '#fafad2'],
    ['lightgray', '#d3d3d3'],
    ['lightgreen', '#90ee90'],
    ['lightgrey', '#d3d3d3'],
    ['lightpink', '#ffb6c1'],
    ['lightsalmon', '#ffa07a'],
    ['lightseagreen', '#20b2aa'],
    ['lightskyblue', '#87cefa'],
    ['lightslategray', '#778899'],
    ['lightslategrey', '#778899'],
    ['lightsteelblue', '#b0c4de'],
    ['lightyellow', '#ffffe0'],
    ['lime', '#00ff00'],
    ['limegreen', '#32cd32'],
    ['linen', '#faf0e6'],
    ['magenta', '#ff00ff'],
    ['maroon', '#800000'],
    ['mediumaquamarine', '#66cdaa'],
    ['mediumblue', '#0000cd'],
    ['mediumorchid', '#ba55d3'],
    ['mediumpurple', '#9370db'],
    ['mediumseagreen', '#3cb371'],
    ['mediumslateblue', '#7b68ee'],
    ['mediumspringgreen', '#00fa9a'],
    ['mediumturquoise', '#48d1cc'],
    ['mediumvioletred', '#c71585'],
    ['midnightblue', '#191970'],
    ['mintcream', '#f5fffa'],
    ['mistyrose', '#ffe4e1'],
    ['moccasin', '#ffe4b5'],
    ['navajowhite', '#ffdead'],
    ['navy', '#000080'],
    ['oldlace', '#fdf5e6'],
    ['olive', '#808000'],
    ['olivedrab', '#6b8e23'],
    ['orange', '#ffa500'],
    ['orangered', '#ff4500'],
    ['orchid', '#da70d6'],
    ['palegoldenrod', '#eee8aa'],
    ['palegreen', '#98fb98'],
    ['paleturquoise', '#afeeee'],
    ['palevioletred', '#db7093'],
    ['papayawhip', '#ffefd5'],
    ['peachpuff', '#ffdab9'],
    ['peru', '#cd853f'],
    ['pink', '#ffc0cb'],
    ['plum', '#dda0dd'],
    ['powderblue', '#b0e0e6'],
    ['purple', '#800080'],
    ['rebeccapurple', '#663399'],
    ['red', '#ff0000'],
    ['rosybrown', '#bc8f8f'],
    ['royalblue', '#4169e1'],
    ['saddlebrown', '#8b4513'],
    ['salmon', '#fa8072'],
    ['sandybrown', '#f4a460'],
    ['seagreen', '#2e8b57'],
    ['seashell', '#fff5ee'],
    ['sienna', '#a0522d'],
    ['silver', '#c0c0c0'],
    ['skyblue', '#87ceeb'],
    ['slateblue', '#6a5acd'],
    ['slategray', '#708090'],
    ['slategrey', '#708090'],
    ['snow', '#fffafa'],
    ['springgreen', '#00ff7f'],
    ['steelblue', '#4682b4'],
    ['tan', '#d2b48c'],
    ['teal', '#008080'],
    ['thistle', '#d8bfd8'],
    ['tomato', '#ff6347'],
    ['turquoise', '#40e0d0'],
    ['violet', '#ee82ee'],
    ['wheat', '#f5deb3'],
    ['white', '#ffffff'],
    ['whitesmoke', '#f5f5f5'],
    ['yellow', '#ffff00'],
    ['yellowgreen', '#9acd32'],
]);

var __rest = (undefined && undefined.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
const pickerState = /*@__PURE__*/new WeakMap();
var ColorType = /*@__PURE__*/(function (ColorType) {
    ColorType["rgb"] = "RGB";
    ColorType["hex"] = "HEX";
    ColorType["named"] = "NAMED";
    ColorType["hsl"] = "HSL";
return ColorType})(ColorType || (ColorType = {}));
const rgbCallExpRegex = /rgb(?:a)?\(\s*(\d{1,3}%?)\s*,?\s*(\d{1,3}%?)\s*,?\s*(\d{1,3}%?)\s*([,/]\s*0?\.?\d+%?)?\)/;
const hslCallExpRegex = /hsl\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*(,\s*0?\.\d+)?\)/;
const hexRegex = /(^|\b)(#[0-9a-f]{3,9})(\b|$)/i;
function discoverColorsInCSS(syntaxTree, from, to, typeName, doc, language) {
    var _a;
    switch (typeName) {
        case 'AttributeValue': {
            const innerTree = syntaxTree.resolveInner(from, 0).tree;
            if (!innerTree) {
                return null;
            }
            const overlayTree = (_a = innerTree.prop(NodeProp.mounted)) === null || _a === void 0 ? void 0 : _a.tree;
            if ((overlayTree === null || overlayTree === void 0 ? void 0 : overlayTree.type.name) !== 'Styles') {
                return null;
            }
            const ret = [];
            overlayTree.iterate({
                from: 0,
                to: overlayTree.length,
                enter: ({ type, from: overlayFrom, to: overlayTo }) => {
                    const maybeWidgetOptions = discoverColorsInCSS(syntaxTree, 
                    // We add one because the tree doesn't include the
                    // quotation mark from the style tag
                    from + 1 + overlayFrom, from + 1 + overlayTo, type.name, doc);
                    if (maybeWidgetOptions) {
                        if (Array.isArray(maybeWidgetOptions)) {
                            throw new Error('Unexpected nested overlays');
                        }
                        ret.push(maybeWidgetOptions);
                    }
                },
            });
            return ret;
        }
        case 'CallExpression': {
            const callExp = doc.sliceString(from, to);
            const result = parseCallExpression(callExp);
            if (!result) {
                return null;
            }
            return Object.assign(Object.assign({}, result), { from,
                to });
        }
        case 'ColorLiteral': {
            const result = parseColorLiteral(doc.sliceString(from, to));
            if (!result) {
                return null;
            }
            return Object.assign(Object.assign({}, result), { from,
                to });
        }
        case 'ValueName': {
            const colorName = doc.sliceString(from, to);
            const result = parseNamedColor(colorName);
            if (!result) {
                return null;
            }
            return Object.assign(Object.assign({}, result), { from,
                to });
        }
        default:
            return null;
    }
}
function parseCallExpression(callExp) {
    const fn = callExp.slice(0, 3);
    switch (fn) {
        case 'rgb': {
            const match = rgbCallExpRegex.exec(callExp);
            if (!match) {
                return null;
            }
            const [_, r, g, b, a] = match;
            const color = rgbToHex(r, g, b);
            return {
                colorType: ColorType.rgb,
                color,
                alpha: a || '',
            };
        }
        case 'hsl': {
            const match = hslCallExpRegex.exec(callExp);
            if (!match) {
                return null;
            }
            const [_, h, s, l, a] = match;
            const color = hslToHex(h, s, l);
            return {
                colorType: ColorType.hsl,
                color,
                alpha: a || '',
            };
        }
        default:
            return null;
    }
}
function parseColorLiteral(colorLiteral) {
    const match = hexRegex.exec(colorLiteral);
    if (!match) {
        return null;
    }
    const [color, alpha] = toFullHex(colorLiteral);
    return {
        colorType: ColorType.hex,
        color,
        alpha,
    };
}
function parseNamedColor(colorName) {
    const color = namedColors.get(colorName);
    if (!color) {
        return null;
    }
    return {
        colorType: ColorType.named,
        color,
        alpha: '',
    };
}
function colorPickersDecorations(view, discoverColors) {
    const widgets = [];
    const st = syntaxTree(view.state);
    for (const range of view.visibleRanges) {
        st.iterate({
            from: range.from,
            to: range.to,
            enter: ({ type, from, to }) => {
                var _a;
                const maybeWidgetOptions = discoverColors(st, from, to, type.name, view.state.doc, (_a = view.state.facet(language)) === null || _a === void 0 ? void 0 : _a.name);
                if (!maybeWidgetOptions) {
                    return;
                }
                if (!Array.isArray(maybeWidgetOptions)) {
                    widgets.push(Decoration.widget({
                        widget: new ColorPickerWidget(maybeWidgetOptions),
                        side: 1,
                    }).range(maybeWidgetOptions.from));
                    return;
                }
                for (const wo of maybeWidgetOptions) {
                    widgets.push(Decoration.widget({
                        widget: new ColorPickerWidget(wo),
                        side: 1,
                    }).range(wo.from));
                }
            },
        });
    }
    return Decoration.set(widgets);
}
function toFullHex(color) {
    if (color.length === 4) {
        // 3-char hex
        return [
            `#${color[1].repeat(2)}${color[2].repeat(2)}${color[3].repeat(2)}`,
            '',
        ];
    }
    if (color.length === 5) {
        // 4-char hex (alpha)
        return [
            `#${color[1].repeat(2)}${color[2].repeat(2)}${color[3].repeat(2)}`,
            color[4].repeat(2),
        ];
    }
    if (color.length === 9) {
        // 8-char hex (alpha)
        return [`#${color.slice(1, -2)}`, color.slice(-2)];
    }
    return [color, ''];
}
function rgbComponentToHex(component) {
    let numericValue;
    if (component.endsWith('%')) {
        // 0-100%
        const percent = Number(component.slice(0, -1));
        numericValue = Math.round((percent / 100) * 255.0);
    }
    else {
        numericValue = Number(component); // assume 0-255
    }
    return decimalToHex(numericValue);
}
function decimalToHex(decimal) {
    const hex = decimal.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
}
function hexToRGBComponents(hex) {
    const r = hex.slice(1, 3);
    const g = hex.slice(3, 5);
    const b = hex.slice(5, 7);
    return [parseInt(r, 16), parseInt(g, 16), parseInt(b, 16)];
}
function rgbToHex(r, g, b) {
    return `#${rgbComponentToHex(r)}${rgbComponentToHex(g)}${rgbComponentToHex(b)}`;
}
function hslToHex(h, s, l) {
    const sFloat = Number(s) / 100;
    const lFloat = Number(l) / 100;
    const [r, g, b] = hslToRGB(Number(h), sFloat, lFloat);
    return `#${decimalToHex(r)}${decimalToHex(g)}${decimalToHex(b)}`;
}
function hslToRGB(hue, saturation, luminance) {
    // If there is no Saturation it means that it’s a shade of grey.
    // So in that case we just need to convert the Luminance and set R,G and B to that level.
    if (saturation === 0) {
        const value = Math.round(luminance * 255);
        return [value, value, value];
    }
    let temp1;
    // If Luminance is smaller then 0.5 (50%) then temporary_1 = Luminance x (1.0+Saturation)
    if (luminance < 0.5) {
        temp1 = luminance * (1.0 + saturation);
    }
    else {
        // If Luminance is equal or larger then 0.5 (50%) then temporary_1 = Luminance + Saturation – Luminance x Saturation
        temp1 = luminance + saturation - luminance * saturation;
    }
    // temporary_2 = 2 x Luminance – temporary _1
    const temp2 = 2 * luminance - temp1;
    // The next step is to convert the 360 degrees in a circle to 1 by dividing the angle by 360.
    hue = hue / 360.0;
    // And now we need another temporary variable for each color channel, temporary_R, temporary_G and temporary_B.
    // All values need to be between 0 and 1. In our case all the values are between 0 and 1
    const tempR = clamp(hue + 0.333);
    const tempG = hue;
    const tempB = clamp(hue - 0.333);
    const red = hueToRGB(temp1, temp2, tempR);
    const green = hueToRGB(temp1, temp2, tempG);
    const blue = hueToRGB(temp1, temp2, tempB);
    return [
        Math.round(red * 255),
        Math.round(green * 255),
        Math.round(blue * 255),
    ];
}
// If you get a negative value you need to add 1 to it.
// If you get a value above 1 you need to subtract 1 from it.
function clamp(num) {
    if (num < 0) {
        return num + 1;
    }
    if (num > 1) {
        return num - 1;
    }
    return num;
}
/**
 * Now we need to do up to 3 tests to select the correct formula for each color channel. Let’s start with Red.
 *
 * test 1 – If 6 x temporary_R is smaller then 1, Red = temporary_2 + (temporary_1 – temporary_2) x 6 x temporary_R
 * In the case the first test is larger then 1 check the following
 *
 * test 2 – If 2 x temporary_R is smaller then 1, Red = temporary_1
 * In the case the second test also is larger then 1 do the following
 *
 * test 3 – If 3 x temporary_R is smaller then 2, Red = temporary_2 + (temporary_1 – temporary_2) x (0.666 – temporary_R) x 6
 * In the case the third test also is larger then 2 you do the following
 *
 * Red = temporary_2
 */
function hueToRGB(temp1, temp2, tempHue) {
    if (6 * tempHue < 1) {
        return temp2 + (temp1 - temp2) * 6 * tempHue;
    }
    if (2 * tempHue < 1) {
        return temp1;
    }
    if (3 * tempHue < 2) {
        return temp2 + (temp1 - temp2) * (0.666 - tempHue) * 6;
    }
    return temp2;
}
// https://www.niwa.nu/2013/05/math-behind-colorspace-conversions-rgb-hsl/
function rgbToHSL(r, g, b) {
    const redPercent = r / 255;
    const greenPercent = g / 255;
    const bluePercent = b / 255;
    const min = Math.min(redPercent, greenPercent, bluePercent);
    const max = Math.max(redPercent, greenPercent, bluePercent);
    const luminance = (max + min) / 2;
    // If the min and max value are the same, it means that there is no saturation. ...
    // If there is no Saturation, we don’t need to calculate the Hue. So we set it to 0 degrees.
    if (max === min) {
        return [0, 0, luminance];
    }
    let saturation;
    // If Luminance is less or equal to 0.5, then Saturation = (max-min)/(max+min)
    if (luminance <= 0.5) {
        saturation = (max - min) / (max + min);
    }
    else {
        // If Luminance is bigger then 0.5. then Saturation = ( max-min)/(2.0-max-min)
        saturation = (max - min) / (2.0 - max - min);
    }
    let hue;
    // If Red is max, then Hue = (G-B)/(max-min)
    if (max === redPercent) {
        hue = (greenPercent - bluePercent) / (max - min);
    }
    else if (greenPercent === max) {
        // If Green is max, then Hue = 2.0 + (B-R)/(max-min)
        hue = 2.0 + (bluePercent - redPercent) / (max - min);
    }
    else {
        // If Blue is max, then Hue = 4.0 + (R-G)/(max-min)
        hue = 4.0 + (redPercent - greenPercent) / (max - min);
    }
    hue = Math.round(hue * 60); // convert to degrees
    // make hue positive angle/degrees
    while (hue < 0) {
        hue += 360;
    }
    return [hue, saturation, luminance];
}
const wrapperClassName = 'cm-css-color-picker-wrapper';
class ColorPickerWidget extends WidgetType {
    constructor(_a) {
        var { color } = _a, state = __rest(_a, ["color"]);
        super();
        this.state = state;
        this.color = color;
    }
    eq(other) {
        return (other.state.colorType === this.state.colorType &&
            other.color === this.color &&
            other.state.from === this.state.from &&
            other.state.to === this.state.to &&
            other.state.alpha === this.state.alpha);
    }
    toDOM() {
        const picker = document.createElement('input');
        pickerState.set(picker, this.state);
        picker.type = 'color';
        picker.value = this.color;
        const wrapper = document.createElement('span');
        wrapper.appendChild(picker);
        wrapper.className = wrapperClassName;
        return wrapper;
    }
    ignoreEvent() {
        return false;
    }
}
const colorPickerTheme = /*@__PURE__*/EditorView.baseTheme({
    [`.${wrapperClassName}`]: {
        display: 'inline-block',
        outline: '1px solid #eee',
        marginRight: '0.6ch',
        height: '1em',
        width: '1em',
        transform: 'translateY(1px)',
    },
    [`.${wrapperClassName} input[type="color"]`]: {
        cursor: 'pointer',
        height: '100%',
        width: '100%',
        padding: 0,
        border: 'none',
        '&::-webkit-color-swatch-wrapper': {
            padding: 0,
        },
        '&::-webkit-color-swatch': {
            border: 'none',
        },
        '&::-moz-color-swatch': {
            border: 'none',
        },
    },
});
const makeColorPicker = (options) => ViewPlugin.fromClass(class ColorPickerViewPlugin {
    constructor(view) {
        this.decorations = colorPickersDecorations(view, options.discoverColors);
    }
    update(update) {
        if (update.docChanged || update.viewportChanged) {
            this.decorations = colorPickersDecorations(update.view, options.discoverColors);
        }
    }
}, {
    decorations: (v) => v.decorations,
    eventHandlers: {
        change: (e, view) => {
            const target = e.target;
            if (target.nodeName !== 'INPUT' ||
                !target.parentElement ||
                !target.parentElement.classList.contains(wrapperClassName)) {
                return false;
            }
            const data = pickerState.get(target);
            let converted = target.value + data.alpha;
            if (data.colorType === ColorType.rgb) {
                converted = `rgb(${hexToRGBComponents(target.value).join(', ')}${data.alpha})`;
            }
            else if (data.colorType === ColorType.named) {
                // If the hex is an exact match for another named color, prefer retaining name
                for (const [key, value] of namedColors.entries()) {
                    if (value === target.value) {
                        converted = key;
                    }
                }
            }
            else if (data.colorType === ColorType.hsl) {
                const [r, g, b] = hexToRGBComponents(target.value);
                const [h, s, l] = rgbToHSL(r, g, b);
                converted = `hsl(${h}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%${data.alpha})`;
            }
            view.dispatch({
                changes: {
                    from: data.from,
                    to: data.to,
                    insert: converted,
                },
            });
            return true;
        },
    },
});
const colorPicker = [/*@__PURE__*/makeColorPicker({ discoverColors: discoverColorsInCSS }), colorPickerTheme];

export { ColorType, colorPicker, colorPickerTheme, makeColorPicker, parseCallExpression, parseColorLiteral, parseNamedColor, wrapperClassName };
