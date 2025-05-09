import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Formatter } from '../shared';
import { Grid, Matcher, WeekDayFormat } from '../date';
import { CalendarIncrement, DateRange } from '../shared/date';
import { Direction } from '../shared/types';
type RangeCalendarRootContext = {
    modelValue: Ref<DateRange>;
    startValue: Ref<DateValue | undefined>;
    endValue: Ref<DateValue | undefined>;
    locale: Ref<string>;
    placeholder: Ref<DateValue>;
    pagedNavigation: Ref<boolean>;
    preventDeselect: Ref<boolean>;
    weekStartsOn: Ref<0 | 1 | 2 | 3 | 4 | 5 | 6>;
    weekdayFormat: Ref<WeekDayFormat>;
    fixedWeeks: Ref<boolean>;
    numberOfMonths: Ref<number>;
    disabled: Ref<boolean>;
    readonly: Ref<boolean>;
    initialFocus: Ref<boolean>;
    onPlaceholderChange: (date: DateValue) => void;
    fullCalendarLabel: Ref<string>;
    parentElement: Ref<HTMLElement | undefined>;
    headingValue: Ref<string>;
    isInvalid: Ref<boolean>;
    isDateDisabled: Matcher;
    isDateUnavailable?: Matcher;
    isOutsideVisibleView: (date: DateValue) => boolean;
    highlightedRange: Ref<{
        start: DateValue;
        end: DateValue;
    } | null>;
    focusedValue: Ref<DateValue | undefined>;
    lastPressedDateValue: Ref<DateValue | undefined>;
    isSelected: (date: DateValue) => boolean;
    isSelectionEnd: (date: DateValue) => boolean;
    isSelectionStart: (date: DateValue) => boolean;
    isHighlightedStart: (date: DateValue) => boolean;
    isHighlightedEnd: (date: DateValue) => boolean;
    prevPage: (step?: CalendarIncrement, prevPageFunc?: (date: DateValue) => DateValue) => void;
    nextPage: (step?: CalendarIncrement, nextPageFunc?: (date: DateValue) => DateValue) => void;
    isNextButtonDisabled: (step?: CalendarIncrement, nextPageFunc?: (date: DateValue) => DateValue) => boolean;
    isPrevButtonDisabled: (step?: CalendarIncrement, prevPageFunc?: (date: DateValue) => DateValue) => boolean;
    formatter: Formatter;
    dir: Ref<Direction>;
};
export interface RangeCalendarRootProps extends PrimitiveProps {
    /** The default placeholder date */
    defaultPlaceholder?: DateValue;
    /** The default value for the calendar */
    defaultValue?: DateRange;
    /** The controlled checked state of the calendar. Can be bound as `v-model`. */
    modelValue?: DateRange;
    /** The placeholder date, which is used to determine what month to display when no date is selected. This updates as the user navigates the calendar and can be used to programmatically control the calendar view */
    placeholder?: DateValue;
    /** This property causes the previous and next buttons to navigate by the number of months displayed at once, rather than one month */
    pagedNavigation?: boolean;
    /** Whether or not to prevent the user from deselecting a date without selecting another date first */
    preventDeselect?: boolean;
    /** The day of the week to start the calendar on */
    weekStartsOn?: 0 | 1 | 2 | 3 | 4 | 5 | 6;
    /** The format to use for the weekday strings provided via the weekdays slot prop */
    weekdayFormat?: WeekDayFormat;
    /** The accessible label for the calendar */
    calendarLabel?: string;
    /** Whether or not to always display 6 weeks in the calendar */
    fixedWeeks?: boolean;
    /** The maximum date that can be selected */
    maxValue?: DateValue;
    /** The minimum date that can be selected */
    minValue?: DateValue;
    /** The locale to use for formatting dates */
    locale?: string;
    /** The number of months to display at once */
    numberOfMonths?: number;
    /** Whether or not the calendar is disabled */
    disabled?: boolean;
    /** Whether or not the calendar is readonly */
    readonly?: boolean;
    /** If true, the calendar will focus the selected day, today, or the first day of the month depending on what is visible when the calendar is mounted */
    initialFocus?: boolean;
    /** A function that returns whether or not a date is disabled */
    isDateDisabled?: Matcher;
    /** A function that returns whether or not a date is unavailable */
    isDateUnavailable?: Matcher;
    /** The reading direction of the calendar when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** A function that returns the next page of the calendar. It receives the current placeholder as an argument inside the component. */
    nextPage?: (placeholder: DateValue) => DateValue;
    /** A function that returns the previous page of the calendar. It receives the current placeholder as an argument inside the component. */
    prevPage?: (placeholder: DateValue) => DateValue;
}
export type RangeCalendarRootEmits = {
    /** Event handler called whenever the model value changes */
    'update:modelValue': [date: DateRange];
    /** Event handler called whenever the placeholder value changes */
    'update:placeholder': [date: DateValue];
    /** Event handler called whenever the start value changes */
    'update:startValue': [date: DateValue | undefined];
};
export declare const injectRangeCalendarRootContext: <T extends RangeCalendarRootContext | null | undefined = RangeCalendarRootContext>(fallback?: T | undefined) => T extends null ? RangeCalendarRootContext | null : RangeCalendarRootContext, provideRangeCalendarRootContext: (contextValue: RangeCalendarRootContext) => RangeCalendarRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<RangeCalendarRootProps>, {
    defaultValue: () => {
        start: undefined;
        end: undefined;
    };
    as: string;
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
    "update:modelValue": (date: DateRange) => void;
    "update:placeholder": (date: DateValue) => void;
    "update:startValue": (date: DateValue | undefined) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<RangeCalendarRootProps>, {
    defaultValue: () => {
        start: undefined;
        end: undefined;
    };
    as: string;
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
    as: import('../Primitive').AsTag | import('vue').Component;
    placeholder: DateValue;
    preventDeselect: boolean;
    weekdayFormat: WeekDayFormat;
    readonly: boolean;
    initialFocus: boolean;
    isDateDisabled: Matcher;
    isDateUnavailable: Matcher;
}, {}>, Readonly<{
    default: (props: {
        /** The current date of the placeholder */
        date: DateValue;
        /** The grid of dates */
        grid: Grid<DateValue>[];
        /** The days of the week */
        weekDays: string[];
        /** The start of the week */
        weekStartsOn: 0 | 1 | 2 | 3 | 4 | 5 | 6;
        /** The calendar locale */
        locale: string;
        /** Whether or not to always display 6 weeks in the calendar */
        fixedWeeks: boolean;
    }) => any;
}> & {
    default: (props: {
        /** The current date of the placeholder */
        date: DateValue;
        /** The grid of dates */
        grid: Grid<DateValue>[];
        /** The days of the week */
        weekDays: string[];
        /** The start of the week */
        weekStartsOn: 0 | 1 | 2 | 3 | 4 | 5 | 6;
        /** The calendar locale */
        locale: string;
        /** Whether or not to always display 6 weeks in the calendar */
        fixedWeeks: boolean;
    }) => any;
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
