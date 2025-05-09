import * as _zag_js_anatomy from '@zag-js/anatomy';
import * as _zag_js_core from '@zag-js/core';
import { EventObject, Machine, Service } from '@zag-js/core';
import { RequiredBy, DirectionProperty, CommonProperties, PropTypes, NormalizeProps } from '@zag-js/types';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"root" | "list" | "trigger" | "content" | "indicator">;

interface ValueChangeDetails {
    value: string;
}
interface FocusChangeDetails {
    focusedValue: string;
}
interface NavigateDetails {
    value: string | null;
    node: HTMLAnchorElement;
}
interface IntlTranslations {
    listLabel?: string | undefined;
}
type ElementIds = Partial<{
    root: string;
    trigger: string;
    list: string;
    content: string;
    indicator: string;
}>;
interface TabsProps extends DirectionProperty, CommonProperties {
    /**
     * The ids of the elements in the tabs. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * Specifies the localized strings that identifies the accessibility elements and their states
     */
    translations?: IntlTranslations | undefined;
    /**
     * Whether the keyboard navigation will loop from last tab to first, and vice versa.
     * @default true
     */
    loopFocus?: boolean | undefined;
    /**
     * The controlled selected tab value
     */
    value?: string | null | undefined;
    /**
     * The initial selected tab value when rendered.
     * Use when you don't need to control the selected tab value.
     */
    defaultValue?: string | null | undefined;
    /**
     * The orientation of the tabs. Can be `horizontal` or `vertical`
     * - `horizontal`: only left and right arrow key navigation will work.
     * - `vertical`: only up and down arrow key navigation will work.
     *
     * @default "horizontal"
     */
    orientation?: "horizontal" | "vertical" | undefined;
    /**
     * The activation mode of the tabs. Can be `manual` or `automatic`
     * - `manual`: Tabs are activated when clicked or press `enter` key.
     * - `automatic`: Tabs are activated when receiving focus
     *
     * @default "automatic"
     */
    activationMode?: "manual" | "automatic" | undefined;
    /**
     * Callback to be called when the selected/active tab changes
     */
    onValueChange?: ((details: ValueChangeDetails) => void) | undefined;
    /**
     * Callback to be called when the focused tab changes
     */
    onFocusChange?: ((details: FocusChangeDetails) => void) | undefined;
    /**
     * Whether the tab is composite
     */
    composite?: boolean | undefined;
    /**
     * Whether the active tab can be deselected when clicking on it.
     */
    deselectable?: boolean | undefined;
    /**
     * Function to navigate to the selected tab when clicking on it.
     * Useful if tab triggers are anchor elements.
     */
    navigate?: ((details: NavigateDetails) => void) | undefined;
}
type PropsWithDefault = "orientation" | "activationMode" | "loopFocus";
type TabsSchema = {
    state: "idle" | "focused";
    props: RequiredBy<TabsProps, PropsWithDefault>;
    context: {
        ssr: boolean;
        value: string | null;
        focusedValue: string | null;
        indicatorTransition: boolean;
        indicatorRect: {
            left: string;
            top: string;
            width: string;
            height: string;
        };
    };
    refs: {
        indicatorCleanup: VoidFunction | null | undefined;
    };
    computed: {
        focused: boolean;
    };
    action: string;
    guard: string;
    effect: string;
    event: EventObject;
};
type TabsService = Service<TabsSchema>;
type TabsMachine = Machine<TabsSchema>;
interface TriggerProps {
    /**
     * The value of the tab
     */
    value: string;
    /**
     * Whether the tab is disabled
     */
    disabled?: boolean | undefined;
}
interface TriggerState {
    /**
     * Whether the tab is selected
     */
    selected: boolean;
    /**
     * Whether the tab is focused
     */
    focused: boolean;
    /**
     * Whether the tab is disabled
     */
    disabled: boolean;
}
interface ContentProps {
    /**
     * The value of the tab
     */
    value: string;
}
interface TabsApi<T extends PropTypes = PropTypes> {
    /**
     * The current value of the tabs.
     */
    value: string | null;
    /**
     * The value of the tab that is currently focused.
     */
    focusedValue: string | null;
    /**
     * Sets the value of the tabs.
     */
    setValue(value: string): void;
    /**
     * Clears the value of the tabs.
     */
    clearValue(): void;
    /**
     * Sets the indicator rect to the tab with the given value
     */
    setIndicatorRect(value: string): void;
    /**
     * Synchronizes the tab index of the content element.
     * Useful when rendering tabs within a select or combobox
     */
    syncTabIndex(): void;
    /**
     * Set focus on the selected tab trigger
     */
    focus(): void;
    /**
     * Selects the next tab
     */
    selectNext(fromValue?: string): void;
    /**
     * Selects the previous tab
     */
    selectPrev(fromValue?: string): void;
    /**
     * Returns the state of the trigger with the given props
     */
    getTriggerState(props: TriggerProps): TriggerState;
    getRootProps(): T["element"];
    getListProps(): T["element"];
    getTriggerProps(props: TriggerProps): T["button"];
    getContentProps(props: ContentProps): T["element"];
    getIndicatorProps(): T["element"];
}

declare function connect<T extends PropTypes>(service: Service<TabsSchema>, normalize: NormalizeProps<T>): TabsApi<T>;

declare const machine: _zag_js_core.Machine<TabsSchema>;

declare const props: (keyof TabsProps)[];
declare const splitProps: <Props extends Partial<TabsProps>>(props: Props) => [Partial<TabsProps>, Omit<Props, keyof TabsProps>];
declare const triggerProps: (keyof TriggerProps)[];
declare const splitTriggerProps: <Props extends TriggerProps>(props: Props) => [TriggerProps, Omit<Props, keyof TriggerProps>];
declare const contentProps: "value"[];
declare const splitContentProps: <Props extends ContentProps>(props: Props) => [ContentProps, Omit<Props, "value">];

export { type TabsApi as Api, type ContentProps, type ElementIds, type FocusChangeDetails, type IntlTranslations, type TabsMachine as Machine, type NavigateDetails, type TabsProps as Props, type TabsService as Service, type TriggerProps, type ValueChangeDetails, anatomy, connect, contentProps, machine, props, splitContentProps, splitProps, splitTriggerProps, triggerProps };
