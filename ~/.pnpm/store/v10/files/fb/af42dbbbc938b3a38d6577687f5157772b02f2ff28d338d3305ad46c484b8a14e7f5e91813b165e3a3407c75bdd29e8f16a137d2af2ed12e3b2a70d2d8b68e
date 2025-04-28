import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
import { Grid, Matcher, WeekDayFormat } from '../date';
import { CalendarIncrement } from '../shared/date';
export type UseCalendarProps = {
    locale: Ref<string>;
    placeholder: Ref<DateValue>;
    weekStartsOn: Ref<0 | 1 | 2 | 3 | 4 | 5 | 6>;
    fixedWeeks: Ref<boolean>;
    numberOfMonths: Ref<number>;
    minValue: Ref<DateValue | undefined>;
    maxValue: Ref<DateValue | undefined>;
    disabled: Ref<boolean>;
    weekdayFormat: Ref<WeekDayFormat>;
    pagedNavigation: Ref<boolean>;
    isDateDisabled?: Matcher;
    isDateUnavailable?: Matcher;
    calendarLabel: Ref<string | undefined>;
    nextPage: Ref<((placeholder: DateValue) => DateValue) | undefined>;
    prevPage: Ref<((placeholder: DateValue) => DateValue) | undefined>;
};
export type UseCalendarStateProps = {
    isDateDisabled: Matcher;
    isDateUnavailable: Matcher;
    date: Ref<DateValue | DateValue[] | undefined>;
};
export declare function useCalendarState(props: UseCalendarStateProps): {
    isDateSelected: (dateObj: DateValue) => boolean;
    isInvalid: import('vue').ComputedRef<boolean>;
};
export declare function useCalendar(props: UseCalendarProps): {
    isDateDisabled: (dateObj: DateValue) => boolean;
    isDateUnavailable: (date: DateValue) => boolean;
    isNextButtonDisabled: (step?: CalendarIncrement, nextPageFunc?: ((date: DateValue) => DateValue) | undefined) => boolean;
    isPrevButtonDisabled: (step?: CalendarIncrement, prevPageFunc?: ((date: DateValue) => DateValue) | undefined) => boolean;
    grid: Ref<Grid<DateValue>[]>;
    weekdays: import('vue').ComputedRef<string[]>;
    visibleView: import('vue').ComputedRef<DateValue[]>;
    isOutsideVisibleView: (date: DateValue) => boolean;
    formatter: import('../shared').Formatter;
    nextPage: (step?: CalendarIncrement, nextPageFunc?: ((date: DateValue) => DateValue) | undefined) => void;
    prevPage: (step?: CalendarIncrement, prevPageFunc?: ((date: DateValue) => DateValue) | undefined) => void;
    headingValue: import('vue').ComputedRef<string>;
    fullCalendarLabel: import('vue').ComputedRef<string>;
};
