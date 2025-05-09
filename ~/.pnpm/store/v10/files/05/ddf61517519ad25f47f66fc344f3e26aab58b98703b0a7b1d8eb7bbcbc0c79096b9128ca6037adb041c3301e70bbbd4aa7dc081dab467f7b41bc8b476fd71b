import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
interface SelectItemContext {
    value: string;
    textId: string;
    disabled: Ref<boolean>;
    isSelected: Ref<boolean>;
    onItemTextChange: (node: HTMLElement | undefined) => void;
}
export declare const injectSelectItemContext: <T extends SelectItemContext | null | undefined = SelectItemContext>(fallback?: T | undefined) => T extends null ? SelectItemContext | null : SelectItemContext, provideSelectItemContext: (contextValue: SelectItemContext) => SelectItemContext;
export interface SelectItemProps extends PrimitiveProps {
    /** The value given as data when submitted with a `name`. */
    value: string;
    /** When `true`, prevents the user from interacting with the item. */
    disabled?: boolean;
    /**
     * Optional text used for typeahead purposes.
     *
     * By default the typeahead behavior will use the `.textContent` of the `SelectItemText` part.
     *
     * Use this when the content is complex, or you have non-textual content inside.
     */
    textValue?: string;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<SelectItemProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<SelectItemProps>>>, {}, {}>, {
    default?(_: {}): any;
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
