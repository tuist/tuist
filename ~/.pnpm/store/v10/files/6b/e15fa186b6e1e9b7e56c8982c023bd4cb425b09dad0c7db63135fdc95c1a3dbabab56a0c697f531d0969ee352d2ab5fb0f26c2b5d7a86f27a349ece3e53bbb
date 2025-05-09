export type PrefetchResult = {
    state: 'idle' | 'loading';
    content: string | null;
    input: string | null;
    url: string | null;
    error: string | null;
};
/**
 * Vue composable for URL prefetching
 */
export declare function useUrlPrefetcher(): {
    prefetchResult: {
        state: "idle" | "loading";
        content: string | null;
        input: string | null;
        url: string | null;
        error: string | null;
    };
    prefetchUrl: (input: string | null, proxy?: string) => Promise<{
        state: string;
        content: null;
        url: null;
        input: string | null;
        error: null;
    } | {
        state: string;
        content: string;
        url: null;
        error: null;
        input?: never;
    } | {
        state: string;
        content: string;
        url: string;
        error: null;
        input?: never;
    } | {
        state: string;
        content: null;
        url: null;
        input: string;
        error: any;
    }>;
    resetPrefetchResult: () => Promise<void>;
};
//# sourceMappingURL=useUrlPrefetcher.d.ts.map