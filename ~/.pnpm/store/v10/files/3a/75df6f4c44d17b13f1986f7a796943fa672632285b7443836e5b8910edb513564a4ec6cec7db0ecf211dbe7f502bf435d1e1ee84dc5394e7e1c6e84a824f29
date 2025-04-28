import { Ref } from 'vue';
interface CollectionContext<ItemData = {}> {
    collectionRef: Ref<HTMLElement | undefined>;
    itemMap: Ref<Map<HTMLElement, {
        ref: HTMLElement;
        value?: any;
    } & ItemData>>;
    attrName: string;
}
export declare const injectCollectionContext: <T extends CollectionContext<{}> | null | undefined = CollectionContext<{}>>(fallback?: T | undefined) => T extends null ? CollectionContext<{}> | null : CollectionContext<{}>, provideCollectionContext: (contextValue: CollectionContext<{}>) => any;
export declare function createCollection<ItemData = {}>(attrName?: string): {
    getItems: () => ({
        ref: HTMLElement;
        value?: any;
    } & ItemData)[];
    reactiveItems: import('vue').ComputedRef<({
        ref: HTMLElement;
        value?: any;
    } & ItemData)[]>;
    itemMapSize: import('vue').ComputedRef<number>;
};
export declare const CollectionSlot: import('vue').DefineComponent<{}, () => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}>, {}, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<{}>>, {}, {}>;
export declare const CollectionItem: import('vue').DefineComponent<{
    value: {
        validator: () => boolean;
    };
}, () => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}>, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<{
    value: {
        validator: () => boolean;
    };
}>>, {}, {}>;
export declare function useCollection<ItemData = {}>(fallback?: CollectionContext<ItemData>): {
    getItems: () => ({
        ref: HTMLElement;
        value?: any;
    } & ItemData)[];
};
export {};
