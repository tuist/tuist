export declare function handleAndDispatchCustomEvent<E extends CustomEvent, OriginalEvent extends Event>(name: string, handler: ((event: E) => void) | undefined, detail: {
    originalEvent: OriginalEvent;
} & (E extends CustomEvent<infer D> ? D : never)): void;
