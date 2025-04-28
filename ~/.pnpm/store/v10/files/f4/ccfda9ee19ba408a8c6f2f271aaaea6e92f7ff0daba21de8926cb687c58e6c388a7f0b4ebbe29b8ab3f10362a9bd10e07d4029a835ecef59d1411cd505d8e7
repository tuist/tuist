import type { ThemeId } from '@scalar/types/legacy';
import alternateTheme from './presets/alternate.css?inline';
import bluePlanetTheme from './presets/bluePlanet.css?inline';
import deepSpaceTheme from './presets/deepSpace.css?inline';
import defaultTheme from './presets/default.css?inline';
import elysiajsTheme from './presets/elysiajs.css?inline';
import fastifyTheme from './presets/fastify.css?inline';
import keplerTheme from './presets/kepler.css?inline';
import marsTheme from './presets/mars.css?inline';
import moonTheme from './presets/moon.css?inline';
import purpleTheme from './presets/purple.css?inline';
import saturnTheme from './presets/saturn.css?inline';
import solarizedTheme from './presets/solarized.css?inline';
export { migrateThemeVariables } from './utilities/legacy.js';
export { hasObtrusiveScrollbars } from './utilities/hasObtrusiveScrollbars.js';
export declare const themeIds: readonly ["alternate", "default", "moon", "purple", "solarized", "bluePlanet", "deepSpace", "saturn", "kepler", "elysiajs", "fastify", "mars", "none"];
export type IntegrationThemeId = 'elysiajs' | 'fastify';
/**
 * Available theme IDs as a type.
 */
export type { ThemeId };
/**
 * User readable theme names / labels
 */
export declare const themeLabels: Record<ThemeId, string>;
/**
 * List of available theme presets.
 */
export declare const presets: Record<Exclude<ThemeId, 'none'>, string>;
/**
 * Get the CSS for the default Scalar fonts
 */
export declare const getDefaultFonts: () => string;
/**
 * List of available theme IDs.
 */
export declare const availableThemes: ThemeId[];
type GetThemeOpts = {
    /**
     * Whether or not to include the base variables (e.g. typography)
     *
     * @default true
     */
    variables?: boolean;
    /**
     * Whether or not to include the definitions for the default scalar fonts (e.g. Inter)
     *
     * @default true
     */
    fonts?: boolean;
    /**
     * Cascade layer to assign the theme styles to
     *
     * @default 'scalar-theme'
     */
    layer?: string | false;
};
/**
 * Get the theme CSS for a given theme ID.
 */
export declare const getThemeById: (themeId?: ThemeId) => string;
/**
 * Get the theme and base variables for a given theme
 */
export declare const getThemeStyles: (themeId?: ThemeId, opts?: GetThemeOpts) => string;
export { alternateTheme };
export { bluePlanetTheme };
export { deepSpaceTheme };
export { defaultTheme };
export { elysiajsTheme };
export { fastifyTheme };
export { keplerTheme };
export { marsTheme };
export { moonTheme };
export { purpleTheme };
export { saturnTheme };
export { solarizedTheme };
//# sourceMappingURL=index.d.ts.map