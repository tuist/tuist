import { Ref, UnwrapNestedRefs, ref } from 'vue';
export declare function useSelectionBehavior<T>(modelValue: Ref<T | T[]>, props: UnwrapNestedRefs<{
    multiple?: boolean;
    selectionBehavior?: 'toggle' | 'replace';
}>): {
    firstValue: Ref<any>;
    onSelectItem: (val: T, condition: (existingValue: T) => boolean) => T | T[];
    handleMultipleReplace: (intent: 'first' | 'last' | 'prev' | 'next', currentElement: HTMLElement | Element | null, getItems: () => {
        ref: HTMLElement;
        value?: any;
    }[], options: any[]) => void;
};
