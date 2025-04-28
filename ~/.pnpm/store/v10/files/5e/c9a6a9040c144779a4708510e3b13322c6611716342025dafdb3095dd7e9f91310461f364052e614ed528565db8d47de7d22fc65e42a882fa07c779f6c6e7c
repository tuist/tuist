import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
import { Matcher } from '../date';
export type UseRangeCalendarProps = {
    start: Ref<DateValue | undefined>;
    end: Ref<DateValue | undefined>;
    isDateDisabled: Matcher;
    isDateUnavailable: Matcher;
    focusedValue: Ref<DateValue | undefined>;
};
export declare function useRangeCalendarState(props: UseRangeCalendarProps): {
    isInvalid: import('vue').ComputedRef<boolean>;
    isSelected: (date: DateValue) => boolean;
    highlightedRange: import('vue').ComputedRef<{
        start: DateValue;
        end: DateValue;
    } | null>;
    isSelectionStart: (date: DateValue) => boolean;
    isSelectionEnd: (date: DateValue) => boolean;
    isHighlightedStart: (date: DateValue) => boolean;
    isHighlightedEnd: (date: DateValue) => boolean;
};
