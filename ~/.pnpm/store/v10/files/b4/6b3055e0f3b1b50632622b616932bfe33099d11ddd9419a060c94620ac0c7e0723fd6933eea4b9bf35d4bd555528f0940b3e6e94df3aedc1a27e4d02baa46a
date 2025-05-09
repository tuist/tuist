import { Ref } from 'vue';
import { SingleOrMultipleProps } from './types';
export declare function useSingleOrMultipleValue<P extends SingleOrMultipleProps, Name extends string>(props: P, emits: (name: Name, ...args: any[]) => void): {
    modelValue: Ref<string | string[] | undefined>;
    type: Ref<"single" | "multiple" | undefined>;
    changeModelValue: (value: string) => void;
    isSingle: import('vue').ComputedRef<boolean>;
};
