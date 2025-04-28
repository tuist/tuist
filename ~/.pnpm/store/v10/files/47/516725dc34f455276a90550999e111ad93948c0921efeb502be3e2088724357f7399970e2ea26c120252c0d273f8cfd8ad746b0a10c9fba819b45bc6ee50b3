import * as _unhead_schema from '@unhead/schema';
import { Unhead } from '@unhead/schema';

interface RenderDomHeadOptions {
    /**
     * Document to use for rendering. Allows stubbing for testing.
     */
    document?: Document;
}
/**
 * Render the head tags to the DOM.
 */
declare function renderDOMHead<T extends Unhead<any>>(head: T, options?: RenderDomHeadOptions): Promise<void>;

interface DebouncedRenderDomHeadOptions extends RenderDomHeadOptions {
    /**
     * Specify a custom delay function for delaying the render.
     */
    delayFn?: (fn: () => void) => void;
}
/**
 * Queue a debounced update of the DOM head.
 */
declare function debouncedRenderDOMHead<T extends Unhead<any>>(head: T, options?: DebouncedRenderDomHeadOptions): Promise<void>;

interface DomPluginOptions extends RenderDomHeadOptions {
    delayFn?: (fn: () => void) => void;
}
declare function DomPlugin(options?: DomPluginOptions): _unhead_schema.HeadPluginInput;

export { type DebouncedRenderDomHeadOptions, DomPlugin, type DomPluginOptions, type RenderDomHeadOptions, debouncedRenderDOMHead, renderDOMHead };
