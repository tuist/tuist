import { PrimitiveProps } from '../Primitive';
export interface MenuItemImplProps extends PrimitiveProps {
    /** When `true`, prevents the user from interacting with the item. */
    disabled?: boolean;
    /**
     * Optional text used for typeahead purposes. By default the typeahead behavior will use the `.textContent` of the item. <br>
     *  Use this when the content is complex, or you have non-textual content inside.
     */
    textValue?: string;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<MenuItemImplProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<MenuItemImplProps>>>, {}, {}>, {
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
