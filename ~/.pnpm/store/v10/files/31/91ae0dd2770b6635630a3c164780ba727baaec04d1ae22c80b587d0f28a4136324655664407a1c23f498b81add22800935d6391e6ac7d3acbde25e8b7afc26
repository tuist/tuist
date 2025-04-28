import { DateValue } from '@internationalized/date';
import { Grid } from './types';
import { DateRange } from '../shared';
export type WeekDayFormat = 'narrow' | 'short' | 'long';
export type CreateSelectProps = {
    /**
     * The date object representing the date (usually the first day of the month/year).
     */
    dateObj: DateValue;
};
export type CreateMonthProps = {
    /**
     * The date object representing the month's date (usually the first day of the month).
     */
    dateObj: DateValue;
    /**
     * The day of the week to start the calendar on (0 for Sunday, 1 for Monday, etc.).
     */
    weekStartsOn: number;
    /**
     * Whether to always render 6 weeks in the calendar, even if the month doesn't
     * span 6 weeks.
     */
    fixedWeeks: boolean;
    /**
     * The locale to use when creating the calendar month.
     */
    locale: string;
};
/**
 * Retrieves an array of date values representing the days between
 * the provided start and end dates.
 */
export declare function getDaysBetween(start: DateValue, end: DateValue): DateValue[];
export declare function createMonth(props: CreateMonthProps): Grid<DateValue>;
type SetMonthProps = CreateMonthProps & {
    numberOfMonths: number | undefined;
    currentMonths?: Grid<DateValue>[];
};
type SetYearProps = CreateSelectProps & {
    numberOfMonths?: number;
    pagedNavigation?: boolean;
};
type SetDecadeProps = CreateSelectProps & {
    startIndex?: number;
    endIndex: number;
};
export declare function startOfDecade(dateObj: DateValue): DateValue;
export declare function endOfDecade(dateObj: DateValue): DateValue;
export declare function createDecade(props: SetDecadeProps): DateValue[];
export declare function createYear(props: SetYearProps): DateValue[];
export declare function createMonths(props: SetMonthProps): Grid<DateValue>[];
export declare function createYearRange({ start, end }: DateRange): DateValue[];
export declare function createDateRange({ start, end }: DateRange): DateValue[];
export {};
