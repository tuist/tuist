import type { Spec, TransformedOperation } from '@scalar/types/legacy';
import { type FuseResult } from 'fuse.js';
import { type Ref } from 'vue';
import { type ParamMap } from '../../hooks';
export type EntryType = 'req' | 'webhook' | 'model' | 'heading' | 'tag';
export type FuseData = {
    title: string;
    href: string;
    type: EntryType;
    operationId?: string;
    description: string;
    body?: string | string[] | ParamMap;
    httpVerb?: string;
    path?: string;
    tag?: string;
    operation?: TransformedOperation;
};
/**
 * Creates the search index from an OpenAPI document.
 */
export declare function useSearchIndex({ specification, }: {
    specification: Ref<Spec>;
}): {
    resetSearch: () => void;
    fuseSearch: () => void;
    selectedSearchResult: Ref<number, number>;
    searchResultsWithPlaceholderResults: import("vue").ComputedRef<FuseResult<FuseData>[]>;
    searchText: Ref<string, string>;
};
//# sourceMappingURL=useSearchIndex.d.ts.map