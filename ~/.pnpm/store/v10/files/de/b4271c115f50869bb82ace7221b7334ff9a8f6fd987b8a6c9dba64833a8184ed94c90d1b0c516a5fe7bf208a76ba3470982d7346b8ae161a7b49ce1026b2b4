import { PrimitiveProps } from '../Primitive';
import { ComputedRef, Ref } from 'vue';
import { AcceptableInputValue } from './TagsInputRoot';
export interface TagsInputItemProps extends PrimitiveProps {
    /** Value associated with the tags */
    value: AcceptableInputValue;
    /** When `true`, prevents the user from interacting with the tags input. */
    disabled?: boolean;
}
export interface TagsInputItemContext {
    value: Ref<AcceptableInputValue>;
    displayValue: ComputedRef<string>;
    isSelected: Ref<boolean>;
    disabled?: Ref<boolean>;
    textId: string;
}
export declare const injectTagsInputItemContext: <T extends TagsInputItemContext | null | undefined = TagsInputItemContext>(fallback?: T | undefined) => T extends null ? TagsInputItemContext | null : TagsInputItemContext, provideTagsInputItemContext: (contextValue: TagsInputItemContext) => TagsInputItemContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<TagsInputItemProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<TagsInputItemProps>>>, {}, {}>, {
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
