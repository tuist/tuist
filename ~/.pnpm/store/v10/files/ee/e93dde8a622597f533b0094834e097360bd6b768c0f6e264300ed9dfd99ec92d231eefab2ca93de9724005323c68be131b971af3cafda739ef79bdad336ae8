import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Formatter } from '../shared';
import { DateRange, Granularity, HourCycle, SegmentPart, SegmentValueObj } from '../shared/date';
import { Matcher } from '../date';
import { Direction } from '../shared/types';
export type DateRangeType = 'start' | 'end';
type DateRangeFieldRootContext = {
    locale: Ref<string>;
    startValue: Ref<DateValue | undefined>;
    endValue: Ref<DateValue | undefined>;
    placeholder: Ref<DateValue>;
    isDateUnavailable?: Matcher;
    isInvalid: Ref<boolean>;
    disabled: Ref<boolean>;
    readonly: Ref<boolean>;
    formatter: Formatter;
    hourCycle: HourCycle;
    segmentValues: Record<DateRangeType, Ref<SegmentValueObj>>;
    segmentContents: Ref<{
        start: {
            part: SegmentPart;
            value: string;
        }[];
        end: {
            part: SegmentPart;
            value: string;
        }[];
    }>;
    elements: Ref<Set<HTMLElement>>;
    focusNext: () => void;
    setFocusedElement: (el: HTMLElement) => void;
};
export interface DateRangeFieldRootProps extends PrimitiveProps {
    /** The default value for the calendar */
    defaultValue?: DateRange;
    /** The default placeholder date */
    defaultPlaceholder?: DateValue;
    /** The placeholder date, which is used to determine what month to display when no date is selected. This updates as the user navigates the calendar and can be used to programmatically control the calendar view */
    placeholder?: DateValue;
    /** The controlled checked state of the calendar. Can be bound as `v-model`. */
    modelValue?: DateRange;
    /** The hour cycle used for formatting times. Defaults to the local preference */
    hourCycle?: HourCycle;
    /** The granularity to use for formatting times. Defaults to day if a CalendarDate is provided, otherwise defaults to minute. The field will render segments for each part of the date up to and including the specified granularity */
    granularity?: Granularity;
    /** Whether or not to hide the time zone segment of the field */
    hideTimeZone?: boolean;
    /** The maximum date that can be selected */
    maxValue?: DateValue;
    /** The minimum date that can be selected */
    minValue?: DateValue;
    /** The locale to use for formatting dates */
    locale?: string;
    /** Whether or not the date field is disabled */
    disabled?: boolean;
    /** Whether or not the date field is readonly */
    readonly?: boolean;
    /** A function that returns whether or not a date is unavailable */
    isDateUnavailable?: Matcher;
    /** The name of the date field. Submitted with its owning form as part of a name/value pair. */
    name?: string; /** When `true`, indicates that the user must check the date field before the owning form can be submitted. */
    /** When `true`, indicates that the user must check the date field before the owning form can be submitted. */
    required?: boolean;
    /** Id of the element */
    id?: string;
    /** The reading direction of the date field when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
}
export type DateRangeFieldRootEmits = {
    /** Event handler called whenever the model value changes */
    'update:modelValue': [DateRange];
    /** Event handler called whenever the placeholder value changes */
    'update:placeholder': [date: DateValue];
};
export declare const injectDateRangeFieldRootContext: <T extends DateRangeFieldRootContext | null | undefined = DateRangeFieldRootContext>(fallback?: T | undefined) => T extends null ? DateRangeFieldRootContext | null : DateRangeFieldRootContext, provideDateRangeFieldRootContext: (contextValue: DateRangeFieldRootContext) => DateRangeFieldRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<DateRangeFieldRootProps>, {
    defaultValue: undefined;
    disabled: boolean;
    readonly: boolean;
    placeholder: undefined;
    locale: string;
    isDateUnavailable: undefined;
}>, {
    setFocusedElement: (el: HTMLElement) => void;
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (args_0: DateRange) => void;
    "update:placeholder": (date: DateValue) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<DateRangeFieldRootProps>, {
    defaultValue: undefined;
    disabled: boolean;
    readonly: boolean;
    placeholder: undefined;
    locale: string;
    isDateUnavailable: undefined;
}>>> & {
    "onUpdate:modelValue"?: ((args_0: DateRange) => any) | undefined;
    "onUpdate:placeholder"?: ((date: DateValue) => any) | undefined;
}, {
    defaultValue: DateRange;
    locale: string;
    disabled: boolean;
    placeholder: DateValue;
    readonly: boolean;
    isDateUnavailable: Matcher;
}, {}>, {
    default?(_: {
        modelValue: DateRange;
        segments: {
            start: {
                part: SegmentPart;
                value: string;
            }[];
            end: {
                part: SegmentPart;
                value: string;
            }[];
        };
    }): any;
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
