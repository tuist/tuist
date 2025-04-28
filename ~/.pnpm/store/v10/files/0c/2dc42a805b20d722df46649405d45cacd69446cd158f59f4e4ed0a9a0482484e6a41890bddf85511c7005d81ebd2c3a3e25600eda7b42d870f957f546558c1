import type { Request } from '@scalar/oas-utils/entities/spec';
import { type FuseResult } from 'fuse.js';
/**
 * Hook for managing search functionality.
 * Provides search state, results, and methods for searching.
 */
export declare function useSearch(): {
    searchText: import("vue").Ref<string, string>;
    searchResultsWithPlaceholderResults: import("vue").ComputedRef<FuseResult<{
        title: string;
        description: string;
        httpVerb: string;
        id: string;
        path: string;
        link: string | undefined;
    }>[]>;
    selectedSearchResult: import("vue").Ref<number, number>;
    onSearchResultClick: (entry: FuseResult<{
        title: string;
        description: string;
        httpVerb: string;
        id: string;
        path: string;
        link: string | undefined;
    }>) => void;
    fuseSearch: () => void;
    searchInputRef: import("vue").Ref<HTMLInputElement | null, HTMLInputElement | null>;
    searchResultRefs: import("vue").Ref<HTMLElement[], HTMLElement[]>;
    navigateSearchResults: (direction: "up" | "down") => void;
    selectSearchResult: () => void;
    populateFuseDataArray: (items: Request[]) => void;
};
//# sourceMappingURL=useSearch.d.ts.map