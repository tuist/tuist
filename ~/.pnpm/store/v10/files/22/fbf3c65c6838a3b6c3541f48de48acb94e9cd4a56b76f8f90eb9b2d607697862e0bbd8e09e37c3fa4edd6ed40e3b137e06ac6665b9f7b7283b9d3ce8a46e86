import { Component, PropType } from 'vue';
export type AsTag = 'a' | 'button' | 'div' | 'form' | 'h2' | 'h3' | 'img' | 'input' | 'label' | 'li' | 'nav' | 'ol' | 'p' | 'span' | 'svg' | 'ul' | 'template' | ({} & string);
export interface PrimitiveProps {
    /**
     * Change the default rendered element for the one passed as a child, merging their props and behavior.
     *
     * Read our [Composition](https://www.radix-vue.com/guides/composition.html) guide for more details.
     */
    asChild?: boolean;
    /**
     * The element or component this component should render as. Can be overwritten by `asChild`.
     * @defaultValue "div"
     */
    as?: AsTag | Component;
}
export declare const Primitive: import('vue').DefineComponent<{
    asChild: {
        type: BooleanConstructor;
        default: boolean;
    };
    as: {
        type: PropType<AsTag | Component>;
        default: string;
    };
}, () => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}>, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<{
    asChild: {
        type: BooleanConstructor;
        default: boolean;
    };
    as: {
        type: PropType<AsTag | Component>;
        default: string;
    };
}>>, {
    asChild: boolean;
    as: AsTag | Component;
}, {}>;
