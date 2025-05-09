import { DefineComponent, VNodeProps } from 'vue';
import { ComponentProps } from 'vue-component-type-helpers';
type RawProps = VNodeProps & {
    __v_isVNode?: never;
    [Symbol.iterator]?: never;
} & Record<string, any>;
interface MountingOptions<Props> {
    /**
     * Default props for the component
     */
    props?: (RawProps & Props) | ({} extends Props ? null : never) | ((attrs: Record<string, any>) => (RawProps & Props));
    /**
     * Pass attributes into the component
     */
    attrs?: Record<string, unknown>;
}
export declare function withDefault<T, C = T extends ((...args: any) => any) | (new (...args: any) => any) ? T : T extends {
    props?: infer Props;
} ? DefineComponent<Props extends Readonly<(infer PropNames)[]> | (infer PropNames)[] ? {
    [key in PropNames extends string ? PropNames : string]?: any;
} : Props> : DefineComponent, P extends ComponentProps<C> = ComponentProps<C>>(originalComponent: T, options?: MountingOptions<P>): T;
export {};
