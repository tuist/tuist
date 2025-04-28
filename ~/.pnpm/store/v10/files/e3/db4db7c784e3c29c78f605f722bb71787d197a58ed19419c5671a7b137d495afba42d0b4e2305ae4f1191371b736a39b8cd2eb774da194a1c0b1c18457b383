export type EmulatedRegExpOptions = {
    strategy?: string | null;
    useEmulationGroups?: boolean;
};
export function applySubclassStrategies(ast: any): "line_or_search_start" | "not_search_start";
/**
@typedef {{
  strategy?: string | null;
  useEmulationGroups?: boolean;
}} EmulatedRegExpOptions
*/
/**
Works the same as JavaScript's native `RegExp` constructor in all contexts, but can be given
results from `toDetails` to produce the same result as `toRegExp`.
@augments RegExp
*/
export class EmulatedRegExp extends RegExp {
    /**
     @overload
     @param {string} pattern
     @param {string} [flags]
     @param {EmulatedRegExpOptions} [options]
     */
    constructor(pattern: string, flags?: string, options?: EmulatedRegExpOptions);
    /**
     @overload
     @param {EmulatedRegExp} pattern
     @param {string} [flags]
     */
    constructor(pattern: EmulatedRegExp, flags?: string);
    /**
    Can be used to serialize the arguments used to create the instance.
    @type {{
      pattern: string;
      flags: string;
      options: EmulatedRegExpOptions;
    }}
    */
    rawArgs: {
        pattern: string;
        flags: string;
        options: EmulatedRegExpOptions;
    };
    #private;
}
export function isLoneGLookaround(node: any, options: any): any;
