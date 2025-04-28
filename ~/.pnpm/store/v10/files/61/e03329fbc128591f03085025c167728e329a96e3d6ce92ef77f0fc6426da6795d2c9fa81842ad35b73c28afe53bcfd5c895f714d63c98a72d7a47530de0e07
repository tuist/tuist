import type { Slot } from 'vue';
import type { ScalarFloatingOptions } from '../ScalarFloating';
import type { Option, OptionGroup } from './types.js';
type Props = {
    options: Option[] | OptionGroup[];
    modelValue?: Option;
    placeholder?: string;
} & ScalarFloatingOptions;
type SlotProps = {
    /** Whether or not the combobox is open */
    open: boolean;
};
declare function __VLS_template(): {
    attrs: Partial<{}>;
    slots: Readonly<{
        /** The reference element for the combobox */
        default(props: SlotProps): Slot;
        /** A slot for contents before the combobox options */
        before?(props: SlotProps): Slot;
        /** A slot for contents after the combobox options */
        after?(props: SlotProps): Slot;
    }> & {
        /** The reference element for the combobox */
        default(props: SlotProps): Slot;
        /** A slot for contents before the combobox options */
        before?(props: SlotProps): Slot;
        /** A slot for contents after the combobox options */
        after?(props: SlotProps): Slot;
    };
    refs: {};
    rootEl: any;
};
type __VLS_TemplateResult = ReturnType<typeof __VLS_template>;
declare const __VLS_component: import("vue").DefineComponent<Props, {}, {}, {}, {}, import("vue").ComponentOptionsMixin, import("vue").ComponentOptionsMixin, {} & {
    "update:modelValue": (v: Option) => any;
}, string, import("vue").PublicProps, Readonly<Props> & Readonly<{
    "onUpdate:modelValue"?: ((v: Option) => any) | undefined;
}>, {}, {}, {}, {}, string, import("vue").ComponentProvideOptions, false, {}, any>;
declare const _default: __VLS_WithTemplateSlots<typeof __VLS_component, __VLS_TemplateResult["slots"]>;
export default _default;
type __VLS_WithTemplateSlots<T, S> = T & {
    new (): {
        $slots: S;
    };
};
//# sourceMappingURL=ScalarCombobox.vue.d.ts.map