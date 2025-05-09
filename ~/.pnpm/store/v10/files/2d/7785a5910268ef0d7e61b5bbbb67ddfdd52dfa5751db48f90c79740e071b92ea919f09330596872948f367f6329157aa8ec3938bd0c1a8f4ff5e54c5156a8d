import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Formatter } from '../shared';
import { Granularity, HourCycle, SegmentPart, SegmentValueObj } from '../shared/date';
import { Matcher } from '../date';
import { Direction } from '../shared/types';
type DateFieldRootContext = {
    locale: Ref<string>;
    modelValue: Ref<DateValue | undefined>;
    placeholder: Ref<DateValue>;
    isDateUnavailable?: Matcher;
    isInvalid: Ref<boolean>;
    disabled: Ref<boolean>;
    readonly: Ref<boolean>;
    formatter: Formatter;
    hourCycle: HourCycle;
    segmentValues: Ref<SegmentValueObj>;
    segmentContents: Ref<{
        part: SegmentPart;
        value: string;
    }[]>;
    elements: Ref<Set<HTMLElement>>;
    focusNext: () => void;
    setFocusedElement: (el: HTMLElement) => void;
};
export interface DateFieldRootProps extends PrimitiveProps {
    /** The default value for the calendar */
    defaultValue?: DateValue;
    /** The default placeholder date */
    defaultPlaceholder?: DateValue;
    /** The placeholder date, which is used to determine what month to display when no date is selected. This updates as the user navigates the calendar and can be used to programmatically control the calendar view */
    placeholder?: DateValue;
    /** The controlled checked state of the calendar. Can be bound as `v-model`. */
    modelValue?: DateValue | undefined;
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
    name?: string;
    /** When `true`, indicates that the user must check the date field before the owning form can be submitted. */
    required?: boolean;
    /** Id of the element */
    id?: string;
    /** The reading direction of the date field when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
}
export type DateFieldRootEmits = {
    /** Event handler called whenever the model value changes */
    'update:modelValue': [date: DateValue | undefined];
    /** Event handler called whenever the placeholder value changes */
    'update:placeholder': [date: DateValue];
};
export declare const injectDateFieldRootContext: <T extends DateFieldRootContext | null | undefined = DateFieldRootContext>(fallback?: T | undefined) => T extends null ? DateFieldRootContext | null : DateFieldRootContext, provideDateFieldRootContext: (contextValue: DateFieldRootContext) => DateFieldRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<DateFieldRootProps>, {
    defaultValue: undefined;
    disabled: boolean;
    readonly: boolean;
    placeholder: undefined;
    locale: string;
    isDateUnavailable: undefined;
}>, {
    /** Helper to set the focused element inside the DateField */
    setFocusedElement: (el: HTMLElement) => void;
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (date: DateValue | undefined) => void;
    "update:placeholder": (date: DateValue) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<DateFieldRootProps>, {
    defaultValue: undefined;
    disabled: boolean;
    readonly: boolean;
    placeholder: undefined;
    locale: string;
    isDateUnavailable: undefined;
}>>> & {
    "onUpdate:modelValue"?: ((date: DateValue | undefined) => any) | undefined;
    "onUpdate:placeholder"?: ((date: DateValue) => any) | undefined;
}, {
    defaultValue: DateValue;
    locale: string;
    disabled: boolean;
    placeholder: DateValue;
    readonly: boolean;
    isDateUnavailable: Matcher;
}, {}>, Readonly<{
    default: (props: {
        /** The current date of the field */
        modelValue: DateValue | undefined;
        /** The date field segment contents */
        segments: {
            part: SegmentPart;
            value: string;
        }[];
        /** Value if the input is invalid */
        isInvalid: boolean;
    }) => any;
}> & {
    default: (props: {
        /** The current date of the field */
        modelValue: DateValue | undefined;
        /** The date field segment contents */
        segments: {
            part: SegmentPart;
            value: string;
        }[];
        /** Value if the input is invalid */
        isInvalid: boolean;
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
