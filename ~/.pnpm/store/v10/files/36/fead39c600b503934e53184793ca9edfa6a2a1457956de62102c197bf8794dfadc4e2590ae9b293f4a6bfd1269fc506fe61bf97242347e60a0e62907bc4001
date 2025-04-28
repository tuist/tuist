interface AnatomyPart {
    selector: string;
    attrs: Record<"data-scope" | "data-part", string>;
}
type AnatomyInstance<T extends string> = Omit<Anatomy<T>, "parts">;
type AnatomyPartName<T> = T extends AnatomyInstance<infer U> ? U : never;
interface Anatomy<T extends string> {
    parts: <U extends string>(...parts: U[]) => AnatomyInstance<U>;
    extendWith: <V extends string>(...parts: V[]) => AnatomyInstance<T | V>;
    build: () => Record<T, AnatomyPart>;
    rename: (newName: string) => Anatomy<T>;
    keys: () => T[];
}
declare const createAnatomy: <T extends string>(name: string, parts?: T[]) => Anatomy<T>;

export { type Anatomy, type AnatomyInstance, type AnatomyPart, type AnatomyPartName, createAnatomy };
