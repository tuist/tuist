import { PrimitiveProps } from '../Primitive';
import { SegmentPart } from '../shared/date';
import { DateRangeType } from './DateRangeFieldRoot';
export interface DateRangeFieldInputProps extends PrimitiveProps {
    /** The part of the date to render */
    part: SegmentPart;
    /** The type of field to render (start or end) */
    type: DateRangeType;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<DateRangeFieldInputProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<DateRangeFieldInputProps>>>, {}, {}>, {
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
