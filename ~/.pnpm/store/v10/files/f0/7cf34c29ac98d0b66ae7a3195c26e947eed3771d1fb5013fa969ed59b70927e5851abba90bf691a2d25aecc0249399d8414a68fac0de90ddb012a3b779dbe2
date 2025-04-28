interface LiveRegionOptions {
    level: "polite" | "assertive";
    document?: Document | undefined;
    root?: HTMLElement | null | undefined;
    delay?: number | undefined;
}
type LiveRegion = ReturnType<typeof createLiveRegion>;
declare function createLiveRegion(opts?: Partial<LiveRegionOptions>): {
    announce: (message: string, delay?: number) => void;
    destroy: () => void;
    toJSON(): string;
};

export { type LiveRegion, type LiveRegionOptions, createLiveRegion };
