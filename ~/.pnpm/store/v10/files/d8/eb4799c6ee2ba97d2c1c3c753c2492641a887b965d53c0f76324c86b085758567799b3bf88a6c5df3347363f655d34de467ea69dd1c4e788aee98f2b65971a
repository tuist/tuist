import { DateValue } from '@internationalized/date';
export interface DateFormatterOptions extends Intl.DateTimeFormatOptions {
    calendar?: string;
}
export type Formatter = {
    getLocale: () => string;
    setLocale: (newLocale: string) => void;
    custom: (date: Date, options: DateFormatterOptions) => string;
    selectedDate: (date: DateValue, includeTime?: boolean) => string;
    dayOfWeek: (date: Date, length?: DateFormatterOptions['weekday']) => string;
    fullMonthAndYear: (date: Date, options?: DateFormatterOptions) => string;
    fullMonth: (date: Date, options?: DateFormatterOptions) => string;
    fullYear: (date: Date, options?: DateFormatterOptions) => string;
    dayPeriod: (date: Date) => string;
    part: (dateObj: DateValue, type: Intl.DateTimeFormatPartTypes, options?: DateFormatterOptions) => string;
    toParts: (date: DateValue, options?: DateFormatterOptions) => Intl.DateTimeFormatPart[];
    getMonths: () => {
        label: string;
        value: number;
    }[];
};
/**
 * Creates a wrapper around the `DateFormatter`, which is
 * an improved version of the {@link Intl.DateTimeFormat} API,
 * that is used internally by the various date builders to
 * easily format dates in a consistent way.
 *
 * @see [DateFormatter](https://react-spectrum.adobe.com/internationalized/date/DateFormatter.html)
 */
export declare function useDateFormatter(initialLocale: string): Formatter;
