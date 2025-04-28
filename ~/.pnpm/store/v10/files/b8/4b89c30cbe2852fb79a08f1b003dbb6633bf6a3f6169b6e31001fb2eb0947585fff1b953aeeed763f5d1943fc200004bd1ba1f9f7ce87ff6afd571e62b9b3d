import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
type PaginationRootContext = {
    page: Ref<number>;
    onPageChange: (value: number) => void;
    pageCount: Ref<number>;
    siblingCount: Ref<number>;
    disabled: Ref<boolean>;
    showEdges: Ref<boolean>;
};
export interface PaginationRootProps extends PrimitiveProps {
    /** The controlled value of the current page. Can be binded as `v-model:page`. */
    page?: number;
    /**
     * The value of the page that should be active when initially rendered.
     *
     * Use when you do not need to control the value state.
     */
    defaultPage?: number;
    /** Number of items per page */
    itemsPerPage?: number;
    /** Number of items in your list */
    total?: number;
    /** Number of sibling should be shown around the current page */
    siblingCount?: number;
    /** When `true`, prevents the user from interacting with item */
    disabled?: boolean;
    /** When `true`, always show first page, last page, and ellipsis */
    showEdges?: boolean;
}
export type PaginationRootEmits = {
    /** Event handler called when the page value changes */
    'update:page': [value: number];
};
export declare const injectPaginationRootContext: <T extends PaginationRootContext | null | undefined = PaginationRootContext>(fallback?: T | undefined) => T extends null ? PaginationRootContext | null : PaginationRootContext, providePaginationRootContext: (contextValue: PaginationRootContext) => PaginationRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<PaginationRootProps>, {
    as: string;
    total: number;
    itemsPerPage: number;
    siblingCount: number;
    defaultPage: number;
    showEdges: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:page": (value: number) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<PaginationRootProps>, {
    as: string;
    total: number;
    itemsPerPage: number;
    siblingCount: number;
    defaultPage: number;
    showEdges: boolean;
}>>> & {
    "onUpdate:page"?: ((value: number) => any) | undefined;
}, {
    as: import('../Primitive').AsTag | import('vue').Component;
    total: number;
    defaultPage: number;
    itemsPerPage: number;
    siblingCount: number;
    showEdges: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current page state */
        page: number;
        /** Number of pages */
        pageCount: number;
    }) => any;
}> & {
    default: (props: {
        /** Current page state */
        page: number;
        /** Number of pages */
        pageCount: number;
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
