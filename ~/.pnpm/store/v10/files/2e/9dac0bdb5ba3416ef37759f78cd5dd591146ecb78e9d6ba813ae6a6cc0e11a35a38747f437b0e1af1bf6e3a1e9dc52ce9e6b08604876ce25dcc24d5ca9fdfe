import { InteractOutsideHandlers } from '@zag-js/interact-outside';
export { FocusOutsideEvent, InteractOutsideEvent, InteractOutsideHandlers, PointerDownOutsideEvent } from '@zag-js/interact-outside';
import { MaybeFunction } from '@zag-js/utils';

type MaybeElement = HTMLElement | null;
type Container = MaybeElement | Array<MaybeElement>;
type NodeOrFn = MaybeFunction<MaybeElement>;
interface DismissableElementHandlers extends InteractOutsideHandlers {
    /**
     * Function called when the escape key is pressed
     */
    onEscapeKeyDown?: ((event: KeyboardEvent) => void) | undefined;
}
interface PersistentElementOptions {
    /**
     * Returns the persistent elements that:
     * - should not have pointer-events disabled
     * - should not trigger the dismiss event
     */
    persistentElements?: Array<() => Element | null> | undefined;
}
interface DismissableElementOptions extends DismissableElementHandlers, PersistentElementOptions {
    /**
     * Whether to log debug information
     */
    debug?: boolean | undefined;
    /**
     * Whether to block pointer events outside the dismissable element
     */
    pointerBlocking?: boolean | undefined;
    /**
     * Function called when the dismissable element is dismissed
     */
    onDismiss: VoidFunction;
    /**
     * Exclude containers from the interact outside event
     */
    exclude?: MaybeFunction<Container> | undefined;
    /**
     * Defer the interact outside event to the next frame
     */
    defer?: boolean | undefined;
    /**
     * Whether to warn when the node is `null` or `undefined`
     */
    warnOnMissingNode?: boolean | undefined;
}
declare function trackDismissableElement(nodeOrFn: NodeOrFn, options: DismissableElementOptions): () => void;
declare function trackDismissableBranch(nodeOrFn: NodeOrFn, options?: {
    defer?: boolean;
}): () => void;

export { type DismissableElementHandlers, type DismissableElementOptions, type PersistentElementOptions, trackDismissableBranch, trackDismissableElement };
