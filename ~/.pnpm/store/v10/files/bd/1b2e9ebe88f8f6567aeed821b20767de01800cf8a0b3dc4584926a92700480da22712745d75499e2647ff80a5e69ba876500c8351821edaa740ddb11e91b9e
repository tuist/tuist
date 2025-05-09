import { DateValue } from '@internationalized/date';
export type Granularity = 'day' | 'hour' | 'minute' | 'second';
type GetDefaultDateProps = {
    defaultValue?: DateValue | DateValue[] | undefined;
    defaultPlaceholder?: DateValue | undefined;
    granularity?: Granularity;
    locale?: string;
};
/**
 * A helper function used throughout the various date builders
 * to generate a default `DateValue` using the `defaultValue`,
 * `defaultPlaceholder`, and `granularity` props.
 *
 * It's important to match the `DateValue` type being used
 * elsewhere in the builder, so they behave according to the
 * behavior the user expects based on the props they've provided.
 *
 */
export declare function getDefaultDate(props: GetDefaultDateProps): DateValue;
export {};
