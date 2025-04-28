/**
 * Escape characters within a value to make it safe to insert directly into a
 * snippet. Takes options which define the escape requirements.
 *
 * This is closely based on the JSON-stringify string serialization algorithm,
 * but generalized for other string delimiters (e.g. " or ') and different escape
 * characters (e.g. Powershell uses `)
 *
 * See https://tc39.es/ecma262/multipage/structured-data.html#sec-quotejsonstring
 * for the complete original algorithm.
 */
export declare function escapeString(rawValue: any, options?: {}): string;
/**
 * Make a string value safe to insert literally into a snippet within single quotes,
 * by escaping problematic characters, including single quotes inside the string,
 * backslashes, newlines, and other special characters.
 *
 * If value is not a string, it will be stringified with .toString() first.
 */
export declare const escapeForSingleQuotes: (value: any) => string;
/**
 * Make a string value safe to insert literally into a snippet within double quotes,
 * by escaping problematic characters, including double quotes inside the string,
 * backslashes, newlines, and other special characters.
 *
 * If value is not a string, it will be stringified with .toString() first.
 */
export declare const escapeForDoubleQuotes: (value: any) => string;
//# sourceMappingURL=escape.d.ts.map