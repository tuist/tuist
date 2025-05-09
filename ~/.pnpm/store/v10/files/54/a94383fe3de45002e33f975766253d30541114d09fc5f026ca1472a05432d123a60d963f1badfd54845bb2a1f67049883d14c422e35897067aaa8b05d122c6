import { Direction } from './types';
type ArrowKeyOptions = 'horizontal' | 'vertical' | 'both';
interface ArrowNavigationOptions {
    /**
     * The arrow key options to allow navigation
     *
     * @defaultValue "both"
     */
    arrowKeyOptions?: ArrowKeyOptions;
    /**
     * The attribute name to find the collection items in the parent element.
     *
     * @defaultValue "data-radix-vue-collection-item"
     */
    attributeName?: string;
    /**
     * The parent element where contains all the collection items, this will collect every item to be used when nav
     * It will be ignored if attributeName is provided
     *
     * @defaultValue []
     */
    itemsArray?: HTMLElement[];
    /**
     * Allow loop navigation. If false, it will stop at the first and last element
     *
     * @defaultValue true
     */
    loop?: boolean;
    /**
     * The orientation of the collection
     *
     * @defaultValue "ltr"
     */
    dir?: Direction;
    /**
     * Prevent the scroll when navigating. This happens when the direction of the
     * key matches the scroll direction of any ancestor scrollable elements.
     *
     * @defaultValue true
     */
    preventScroll?: boolean;
    /**
     * By default all currentElement would trigger navigation. If `true`, currentElement nodeName in the ignore list will return null
     *
     * @defaultValue false
     */
    enableIgnoredElement?: boolean;
    /**
     * Focus the element after navigation
     *
     * @defaultValue false
     */
    focus?: boolean;
}
/**
 * Allow arrow navigation for every html element with data-radix-vue-collection-item tag
 *
 * @param e               Keyboard event
 * @param currentElement  Event initiator element or any element that wants to handle the navigation
 * @param parentElement   Parent element where contains all the collection items, this will collect every item to be used when nav
 * @param options         further options
 * @returns               the navigated html element or null if none
 */
export declare function useArrowNavigation(e: KeyboardEvent, currentElement: HTMLElement, parentElement: HTMLElement | undefined, options?: ArrowNavigationOptions): HTMLElement | null;
export {};
