import { Granularity, HourCycle, SegmentContentObj, SegmentPart, SegmentValueObj } from '../../shared/date';
import { Formatter } from '../../shared';
import { DateValue } from '@internationalized/date';
import { Ref } from 'vue';
type SyncSegmentValuesProps = {
    value: DateValue;
    formatter: Formatter;
};
export declare function syncSegmentValues(props: SyncSegmentValuesProps): SegmentValueObj;
export declare function initializeSegmentValues(granularity: Granularity): SegmentValueObj;
type SharedContentProps = {
    granularity: Granularity;
    dateRef: DateValue;
    formatter: Formatter;
    hideTimeZone: boolean;
    hourCycle: HourCycle;
};
type CreateContentObjProps = SharedContentProps & {
    segmentValues: SegmentValueObj;
    locale: Ref<string>;
};
type CreateContentProps = CreateContentObjProps;
export declare function createContent(props: CreateContentProps): {
    obj: SegmentContentObj;
    arr: {
        part: SegmentPart;
        value: string;
    }[];
};
export {};
