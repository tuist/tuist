import { PrimitiveProps } from '../Primitive';
import { CalendarIncrement } from '../shared/date';
import { DateValue } from '@internationalized/date';
export interface CalendarPrevProps extends PrimitiveProps {
    /**
     * The calendar unit to go back
     * @deprecated Use `prevPage` instead
     */
    step?: CalendarIncrement;
    /** The function to be used for the prev page. Overwrites the `prevPage` function set on the `CalendarRoot`. */
    prevPage?: (placeholder: DateValue) => DateValue;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<CalendarPrevProps>, {
    as: string;
    step: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<CalendarPrevProps>, {
    as: string;
    step: string;
}>>>, {
    as: import('../Primitive').AsTag | import('vue').Component;
    step: CalendarIncrement;
}, {}>, {
    default?(_: {}): any;
}>;
export default _default;
type __VLS_WithDefaults<P, D> = {
    [K in keyof Pick<P, keyof P>]: K extends keyof D ? __VLS_PrettifyLocal<P[K] & {
        default: D[K];
    }> : P[K];
};
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
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
