type Modality = "keyboard" | "pointer" | "virtual";
type RootNode = Document | ShadowRoot | Node;
interface GlobalListenerData {
    focus: VoidFunction;
}
declare let listenerMap: Map<Window, GlobalListenerData>;
declare function getInteractionModality(): Modality | null;
declare function setInteractionModality(modality: Modality): void;
interface InteractionModalityChangeDetails {
    /** The modality of the interaction that caused the focus to be visible. */
    modality: Modality | null;
}
interface InteractionModalityProps {
    /** The root element to track focus visibility for. */
    root?: RootNode | undefined;
    /** Callback to be called when the interaction modality changes. */
    onChange: (details: InteractionModalityChangeDetails) => void;
}
declare function trackInteractionModality(props: InteractionModalityProps): VoidFunction;
declare function isFocusVisible(): boolean;
interface FocusVisibleChangeDetails {
    /** Whether keyboard focus is visible globally. */
    isFocusVisible: boolean;
    /** The modality of the interaction that caused the focus to be visible. */
    modality: Modality | null;
}
interface FocusVisibleProps {
    /** The root element to track focus visibility for. */
    root?: RootNode | undefined;
    /** Whether the element is a text input. */
    isTextInput?: boolean | undefined;
    /** Whether the element will be auto focused. */
    autoFocus?: boolean | undefined;
    /** Callback to be called when the focus visibility changes. */
    onChange?: ((details: FocusVisibleChangeDetails) => void) | undefined;
}
declare function trackFocusVisible(props?: FocusVisibleProps): VoidFunction;

export { type FocusVisibleChangeDetails, type FocusVisibleProps, type InteractionModalityChangeDetails, type InteractionModalityProps, type Modality, getInteractionModality, isFocusVisible, listenerMap, setInteractionModality, trackFocusVisible, trackInteractionModality };
