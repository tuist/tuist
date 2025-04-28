import { CalendarDateTime, DateValue, ZonedDateTime } from '@internationalized/date';
import { Matcher } from './types';
/**
 * Given a date string and a reference `DateValue` object, parse the
 * string to the same type as the reference object.
 *
 * Useful for parsing strings from data attributes, which are always
 * strings, to the same type being used by the date component.
 */
export declare function parseStringToDateValue(dateStr: string, referenceVal: DateValue): DateValue;
/**
 * Given a `DateValue` object, convert it to a native `Date` object.
 * If a timezone is provided, the date will be converted to that timezone.
 * If no timezone is provided, the date will be converted to the local timezone.
 */
export declare function toDate(dateValue: DateValue, tz?: string): Date;
export declare function isCalendarDateTime(dateValue: DateValue): dateValue is CalendarDateTime;
export declare function isZonedDateTime(dateValue: DateValue): dateValue is ZonedDateTime;
export declare function hasTime(dateValue: DateValue): boolean;
/**
 * Given a date, return the number of days in the month.
 */
export declare function getDaysInMonth(date: Date | DateValue): number;
/**
 * Determine if a date is before the reference date.
 * @param dateToCompare - is this date before the `referenceDate`
 * @param referenceDate - is the `dateToCompare` before this date
 *
 * @see {@link isBeforeOrSame} for inclusive
 */
export declare function isBefore(dateToCompare: DateValue, referenceDate: DateValue): boolean;
/**
 * Determine if a date is after the reference date.
 * @param dateToCompare - is this date after the `referenceDate`
 * @param referenceDate - is the `dateToCompare` after this date
 *
 * @see {@link isAfterOrSame} for inclusive
 */
export declare function isAfter(dateToCompare: DateValue, referenceDate: DateValue): boolean;
/**
 * Determine if a date is before or the same as the reference date.
 *
 * @param dateToCompare - the date to compare
 * @param referenceDate - the reference date to make the comparison against
 *
 * @see {@link isBefore} for non-inclusive
 */
export declare function isBeforeOrSame(dateToCompare: DateValue, referenceDate: DateValue): boolean;
/**
 * Determine if a date is after or the same as the reference date.
 *
 * @param dateToCompare - is this date after or the same as the `referenceDate`
 * @param referenceDate - is the `dateToCompare` after or the same as this date
 *
 * @see {@link isAfter} for non-inclusive
 */
export declare function isAfterOrSame(dateToCompare: DateValue, referenceDate: DateValue): boolean;
/**
 * Determine if a date is inclusively between a start and end reference date.
 *
 * @param date - is this date inclusively between the `start` and `end` dates
 * @param start - the start reference date to make the comparison against
 * @param end - the end reference date to make the comparison against
 *
 * @see {@link isBetween} for non-inclusive
 */
export declare function isBetweenInclusive(date: DateValue, start: DateValue, end: DateValue): boolean;
/**
 * Determine if a date is between a start and end reference date.
 *
 * @param date - is this date between the `start` and `end` dates
 * @param start - the start reference date to make the comparison against
 * @param end - the end reference date to make the comparison against
 *
 * @see {@link isBetweenInclusive} for inclusive
 */
export declare function isBetween(date: DateValue, start: DateValue, end: DateValue): boolean;
export declare function getLastFirstDayOfWeek<T extends DateValue = DateValue>(date: T, firstDayOfWeek: number, locale: string): T;
export declare function getNextLastDayOfWeek<T extends DateValue = DateValue>(date: T, firstDayOfWeek: number, locale: string): T;
export declare function areAllDaysBetweenValid(start: DateValue, end: DateValue, isUnavailable: Matcher | undefined, isDisabled: Matcher | undefined): boolean;
