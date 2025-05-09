import { MaybeComputedElementRef } from '@vueuse/core';
import { Ref } from 'vue';
export declare function usePressedHold(options: {
    target?: MaybeComputedElementRef;
    disabled: Ref<boolean>;
}): {
    isPressed: Ref<boolean>;
    onTrigger: import('@vueuse/shared').EventHookOn<any>;
};
export declare function useNumberFormatter(locale: Ref<string>, options?: Ref<Intl.NumberFormatOptions | undefined>): {
    format: (value: number) => string;
    formatToParts: (value: number) => Intl.NumberFormatPart[];
    formatRange: (start: number, end: number) => string;
    formatRangeToParts: (start: number, end: number) => import('@internationalized/number').NumberRangeFormatPart[];
    resolvedOptions: () => Intl.ResolvedNumberFormatOptions;
};
export declare function useNumberParser(locale: Ref<string>, options?: Ref<Intl.NumberFormatOptions | undefined>): {
    parse: (value: string) => number;
    isValidPartialNumber: (value: string, minValue?: number | undefined, maxValue?: number | undefined) => boolean;
    getNumberingSystem: (value: string) => string;
};
export declare function handleDecimalOperation(operator: '-' | '+', value1: number, value2: number): number;
