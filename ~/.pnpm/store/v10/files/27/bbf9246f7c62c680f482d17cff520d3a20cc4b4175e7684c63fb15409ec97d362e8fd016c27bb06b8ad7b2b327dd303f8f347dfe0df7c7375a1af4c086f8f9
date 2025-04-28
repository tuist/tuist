import { Ref } from 'vue';
type ContextValue = Ref<HTMLElement[]>;
/**
 * Composables for provide/inject collections
 * @param key (optional) Name to replace the default `Symbol()` as provide's key
 * @param name (optional) Name to replace the default `ITEM_DATA_ATTR` for the item's attributes
 */
export declare function useCollection(key?: string, name?: string): {
    createCollection: (sourceRef?: Ref<HTMLElement | undefined>) => Ref<HTMLElement[]>;
    injectCollection: () => ContextValue;
};
export {};
