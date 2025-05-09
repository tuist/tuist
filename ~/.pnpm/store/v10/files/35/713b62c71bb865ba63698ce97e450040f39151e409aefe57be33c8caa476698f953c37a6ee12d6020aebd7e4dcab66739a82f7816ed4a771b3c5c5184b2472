import { ComputedRef, VNodeRef } from 'vue';
import { CollapsibleRootProps } from '../Collapsible';
declare enum AccordionItemState {
    Open = "open",
    Closed = "closed"
}
export interface AccordionItemProps extends Omit<CollapsibleRootProps, 'open' | 'defaultOpen' | 'onOpenChange'> {
    /**
     * Whether or not an accordion item is disabled from user interaction.
     * When `true`, prevents the user from interacting with the item.
     *
     * @defaultValue false
     */
    disabled?: boolean;
    /**
     * A string value for the accordion item. All items within an accordion should use a unique value.
     */
    value: string;
}
interface AccordionItemContext {
    open: ComputedRef<boolean>;
    dataState: ComputedRef<AccordionItemState>;
    disabled: ComputedRef<boolean>;
    dataDisabled: ComputedRef<'' | undefined>;
    triggerId: string;
    currentRef: VNodeRef;
    currentElement: ComputedRef<HTMLElement | undefined>;
    value: ComputedRef<string>;
}
export declare const injectAccordionItemContext: <T extends AccordionItemContext | null | undefined = AccordionItemContext>(fallback?: T | undefined) => T extends null ? AccordionItemContext | null : AccordionItemContext, provideAccordionItemContext: (contextValue: AccordionItemContext) => AccordionItemContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<AccordionItemProps>, {
    open: ComputedRef<boolean>;
    dataDisabled: ComputedRef<"" | undefined>;
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<AccordionItemProps>>>, {}, {}>, Readonly<{
    default: (props: {
        /** Current open state */
        open: boolean;
    }) => any;
}> & {
    default: (props: {
        /** Current open state */
        open: boolean;
    }) => any;
}>;
export default _default;
type __VLS_NonUndefinedable<T> = T extends undefined ? never : T;
type __VLS_TypePropsToOption<T> = {
    [K in keyof T]-?: {} extends Pick<T, K> ? {
        type: import('vue').PropType<__VLS_NonUndefinedable<T[K]>>;
    } : {
        type: import('vue').PropType<T[K]>;
        required: true;
    };
};
type __VLS_WithTemplateSlots<T, S> = T & {
    new (): {
        $slots: S;
    };
};
