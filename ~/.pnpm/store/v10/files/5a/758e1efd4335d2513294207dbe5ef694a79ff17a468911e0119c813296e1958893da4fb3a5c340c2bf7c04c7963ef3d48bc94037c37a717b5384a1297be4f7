import { Formatter } from '../shared';
import { HourCycle, SegmentPart, SegmentValueObj } from '../shared/date';
import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
type SegmentAttrProps = {
    disabled: boolean;
    segmentValues: SegmentValueObj;
    hourCycle: HourCycle;
    placeholder: DateValue;
    formatter: Formatter;
};
declare function daySegmentAttrs(props: SegmentAttrProps): {
    'aria-label': string;
    'aria-valuemin': number;
    'aria-valuemax': number;
    'aria-valuenow': number;
    'aria-valuetext': string;
    'data-placeholder': string | undefined;
    role: string;
    contenteditable: boolean;
    tabindex: number | undefined;
    spellcheck: boolean;
    inputmode: string;
    autocorrect: string;
    enterkeyhint: string;
    style: string;
};
declare function monthSegmentAttrs(props: SegmentAttrProps): {
    'aria-label': string;
    contenteditable: boolean;
    'aria-valuemin': number;
    'aria-valuemax': number;
    'aria-valuenow': number;
    'aria-valuetext': string;
    'data-placeholder': string | undefined;
    role: string;
    tabindex: number | undefined;
    spellcheck: boolean;
    inputmode: string;
    autocorrect: string;
    enterkeyhint: string;
    style: string;
};
declare function yearSegmentAttrs(props: SegmentAttrProps): {
    'aria-label': string;
    'aria-valuemin': number;
    'aria-valuemax': number;
    'aria-valuenow': number;
    'aria-valuetext': string;
    'data-placeholder': string | undefined;
    role: string;
    contenteditable: boolean;
    tabindex: number | undefined;
    spellcheck: boolean;
    inputmode: string;
    autocorrect: string;
    enterkeyhint: string;
    style: string;
};
declare function hourSegmentAttrs(props: SegmentAttrProps): {};
declare function minuteSegmentAttrs(props: SegmentAttrProps): {};
declare function secondSegmentAttrs(props: SegmentAttrProps): {};
declare function dayPeriodSegmentAttrs(props: SegmentAttrProps): {};
declare function literalSegmentAttrs(_props: SegmentAttrProps): {
    'aria-hidden': boolean;
    'data-segment': string;
};
declare function timeZoneSegmentAttrs(props: SegmentAttrProps): {
    role: string;
    'aria-label': string;
    'data-readonly': boolean;
    'data-segment': string;
    tabindex: number | undefined;
    style: string;
};
declare function eraSegmentAttrs(props: SegmentAttrProps): {
    'aria-label': string;
    'aria-valuemin': number;
    'aria-valuemax': number;
    'aria-valuenow': number;
    'aria-valuetext': unknown;
    role: string;
    contenteditable: boolean;
    tabindex: number | undefined;
    spellcheck: boolean;
    inputmode: string;
    autocorrect: string;
    enterkeyhint: string;
    style: string;
};
export declare const segmentBuilders: {
    day: {
        attrs: typeof daySegmentAttrs;
    };
    month: {
        attrs: typeof monthSegmentAttrs;
    };
    year: {
        attrs: typeof yearSegmentAttrs;
    };
    hour: {
        attrs: typeof hourSegmentAttrs;
    };
    minute: {
        attrs: typeof minuteSegmentAttrs;
    };
    second: {
        attrs: typeof secondSegmentAttrs;
    };
    dayPeriod: {
        attrs: typeof dayPeriodSegmentAttrs;
    };
    literal: {
        attrs: typeof literalSegmentAttrs;
    };
    timeZoneName: {
        attrs: typeof timeZoneSegmentAttrs;
    };
    era: {
        attrs: typeof eraSegmentAttrs;
    };
};
export type UseDateFieldProps = {
    hasLeftFocus: Ref<boolean>;
    lastKeyZero: Ref<boolean>;
    placeholder: Ref<DateValue>;
    hourCycle: HourCycle;
    formatter: Formatter;
    segmentValues: Ref<SegmentValueObj>;
    disabled: Ref<boolean>;
    readonly: Ref<boolean>;
    part: SegmentPart;
    modelValue: Ref<DateValue | undefined>;
    focusNext: () => void;
};
export declare function useDateField(props: UseDateFieldProps): {
    handleSegmentClick: (e: MouseEvent) => void;
    handleSegmentKeydown: (e: KeyboardEvent) => void;
    attributes: import('vue').ComputedRef<{}>;
};
export {};
