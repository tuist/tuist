import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
import { DateRange, Granularity, HourCycle } from '../shared/date';
import { Matcher, WeekDayFormat } from '../date';
import { DateRangeFieldRoot, DateRangeFieldRootProps, PopoverRootProps, RangeCalendarRootProps } from '..';
import { Direction } from '../shared/types';
type DateRangePickerRootContext = {
    id: Ref<string | undefined>;
    name: Ref<string | undefined>;
    minValue: Ref<DateValue | undefined>;
    maxValue: Ref<DateValue | undefined>;
    hourCycle: Ref<HourCycle | undefined>;
    granularity: Ref<Granularity | undefined>;
    hideTimeZone: Ref<boolean>;
    required: Ref<boolean>;
    locale: Ref<string>;
    dateFieldRef: Ref<InstanceType<typeof DateRangeFieldRoot> | undefined>;
    modelValue: Ref<{
        start: DateValue | undefined;
        end: DateValue | undefined;
    }>;
    placeholder: Ref<DateValue>;
    pagedNavigation: Ref<boolean>;
    preventDeselect: Ref<boolean>;
    weekStartsOn: Ref<0 | 1 | 2 | 3 | 4 | 5 | 6>;
    weekdayFormat: Ref<WeekDayFormat>;
    fixedWeeks: Ref<boolean>;
    numberOfMonths: Ref<number>;
    disabled: Ref<boolean>;
    readonly: Ref<boolean>;
    isDateDisabled?: Matcher;
    isDateUnavailable?: Matcher;
    defaultOpen: Ref<boolean>;
    open: Ref<boolean>;
    modal: Ref<boolean>;
    onDateChange: (date: DateRange) => void;
    onPlaceholderChange: (date: DateValue) => void;
    onStartValueChange: (date: DateValue | undefined) => void;
    dir: Ref<Direction>;
};
export type DateRangePickerRootProps = DateRangeFieldRootProps & PopoverRootProps & Pick<RangeCalendarRootProps, 'isDateDisabled' | 'pagedNavigation' | 'weekStartsOn' | 'weekdayFormat' | 'fixedWeeks' | 'numberOfMonths' | 'preventDeselect'>;
export type DateRangePickerRootEmits = {
    /** Event handler called whenever the model value changes */
    'update:modelValue': [date: DateRange];
    /** Event handler called whenever the placeholder value changes */
    'update:placeholder': [date: DateValue];
    /** Event handler called whenever the start value changes */
    'update:startValue': [date: DateValue | undefined];
};
export declare const injectDateRangePickerRootContext: <T extends DateRangePickerRootContext | null | undefined = DateRangePickerRootContext>(fallback?: T | undefined) => T extends null ? DateRangePickerRootContext | null : DateRangePickerRootContext, provideDateRangePickerRootContext: (contextValue: DateRangePickerRootContext) => DateRangePickerRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<DateRangePickerRootProps>, {
    defaultValue: () => {
        start: undefined;
        end: undefined;
    };
    defaultOpen: boolean;
    open: undefined;
    modal: boolean;
    pagedNavigation: boolean;
    preventDeselect: boolean;
    weekStartsOn: number;
    weekdayFormat: string;
    fixedWeeks: boolean;
    numberOfMonths: number;
    disabled: boolean;
    readonly: boolean;
    initialFocus: boolean;
    placeholder: undefined;
    locale: string;
    isDateDisabled: undefined;
    isDateUnavailable: undefined;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (value: boolean) => void;
    "update:modelValue": (date: DateRange) => void;
    "update:placeholder": (date: DateValue) => void;
    "update:startValue": (date: DateValue | undefined) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<DateRangePickerRootProps>, {
    defaultValue: () => {
        start: undefined;
        end: undefined;
    };
    defaultOpen: boolean;
    open: undefined;
    modal: boolean;
    pagedNavigation: boolean;
    preventDeselect: boolean;
    weekStartsOn: number;
    weekdayFormat: string;
    fixedWeeks: boolean;
    numberOfMonths: number;
    disabled: boolean;
    readonly: boolean;
    initialFocus: boolean;
    placeholder: undefined;
    locale: string;
    isDateDisabled: undefined;
    isDateUnavailable: undefined;
}>>> & {
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
    "onUpdate:modelValue"?: ((date: DateRange) => any) | undefined;
    "onUpdate:placeholder"?: ((date: DateValue) => any) | undefined;
    "onUpdate:startValue"?: ((date: DateValue | undefined) => any) | undefined;
}, {
    defaultValue: DateRange;
    locale: string;
    disabled: boolean;
    weekStartsOn: 0 | 2 | 1 | 3 | 4 | 5 | 6;
    fixedWeeks: boolean;
    numberOfMonths: number;
    pagedNavigation: boolean;
    defaultOpen: boolean;
    open: boolean;
    modal: boolean;
    placeholder: DateValue;
    preventDeselect: boolean;
    weekdayFormat: WeekDayFormat;
    readonly: boolean;
    isDateDisabled: Matcher;
    isDateUnavailable: Matcher;
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
