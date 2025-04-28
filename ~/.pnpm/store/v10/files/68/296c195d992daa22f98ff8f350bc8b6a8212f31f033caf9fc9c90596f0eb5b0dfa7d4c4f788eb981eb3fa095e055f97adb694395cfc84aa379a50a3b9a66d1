type ClassValue = ClassArray | ClassDictionary | string | number | null | boolean | undefined;
type ClassDictionary = Record<string, any>;
type ClassArray = ClassValue[];
type OmitUndefined<T> = T extends undefined ? never : T;
type StringToBoolean<T> = T extends "true" | "false" ? boolean : T;
type UnionToIntersection<U> = (U extends any ? (k: U) => void : never) extends (k: infer I) => void ? I : never;
export type VariantProps<Component extends (...args: any) => any> = Omit<OmitUndefined<Parameters<Component>[0]>, "class" | "className">;
export interface Compose {
    <T extends ReturnType<CVA>[]>(...components: [...T]): (props?: (UnionToIntersection<{
        [K in keyof T]: VariantProps<T[K]>;
    }[number]> | undefined) & CVAClassProp) => string;
}
export interface CX {
    (...inputs: ClassValue[]): string;
}
export type CXOptions = Parameters<CX>;
export type CXReturn = ReturnType<CX>;
type CVAConfigBase = {
    base?: ClassValue;
};
type CVAVariantShape = Record<string, Record<string, ClassValue>>;
type CVAVariantSchema<V extends CVAVariantShape> = {
    [Variant in keyof V]?: StringToBoolean<keyof V[Variant]> | undefined;
};
type CVAClassProp = {
    class?: ClassValue;
    className?: never;
} | {
    class?: never;
    className?: ClassValue;
};
export interface CVA {
    <_ extends "cva's generic parameters are restricted to internal use only.", V>(config: V extends CVAVariantShape ? CVAConfigBase & {
        variants?: V;
        compoundVariants?: (V extends CVAVariantShape ? (CVAVariantSchema<V> | {
            [Variant in keyof V]?: StringToBoolean<keyof V[Variant]> | StringToBoolean<keyof V[Variant]>[] | undefined;
        }) & CVAClassProp : CVAClassProp)[];
        defaultVariants?: CVAVariantSchema<V>;
    } : CVAConfigBase & {
        variants?: never;
        compoundVariants?: never;
        defaultVariants?: never;
    }): (props?: V extends CVAVariantShape ? CVAVariantSchema<V> & CVAClassProp : CVAClassProp) => string;
}
export interface DefineConfigOptions {
    hooks?: {
        /**
         * @deprecated please use `onComplete`
         */
        "cx:done"?: (className: string) => string;
        /**
         * Returns the completed string of concatenated classes/classNames.
         */
        onComplete?: (className: string) => string;
    };
}
export interface DefineConfig {
    (options?: DefineConfigOptions): {
        compose: Compose;
        cx: CX;
        cva: CVA;
    };
}
export declare const defineConfig: DefineConfig;
export declare const compose: Compose, cva: CVA, cx: CX;
export {};
