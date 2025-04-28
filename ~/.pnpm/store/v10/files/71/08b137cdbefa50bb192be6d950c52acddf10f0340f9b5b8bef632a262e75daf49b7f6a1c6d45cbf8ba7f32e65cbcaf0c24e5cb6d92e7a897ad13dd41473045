import { VirtualItem, Virtualizer } from '@tanstack/vue-virtual';
import { FlattenedItem } from './TreeRoot';
export interface TreeVirtualizerProps {
    /** Estimated size (in px) of each item */
    estimateSize?: number;
    /** text content for each item to achieve type-ahead feature */
    textContent?: (item: Record<string, any>) => string;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<TreeVirtualizerProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<TreeVirtualizerProps>>>, {}, {}>, Readonly<{
    default: (props: {
        item: FlattenedItem<Record<string, any>>;
        virtualizer: Virtualizer<Element | Window, Element>;
        virtualItem: VirtualItem<Element>;
    }) => any;
}> & {
    default: (props: {
        item: FlattenedItem<Record<string, any>>;
        virtualizer: Virtualizer<Element | Window, Element>;
        virtualItem: VirtualItem<Element>;
    }) => any;
}>;
export default _default;
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
