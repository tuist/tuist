import type { StoryObj } from '@storybook/vue3';
/**
 * Provides a wrapper around the `cx` function that merges the
 * component's class attribute with the provided classes.
 *
 * This allows you to override tailwind classes from the parent component and `cx`
 * will intelligently merge them while passing through other attributes.
 *
 * ### Example
 *
 * Scroll down for a working playground which mounts `MockComponent`.
 *
 * ```html
 * <script setup>
 * import { useBindCx, cva } from '@scalar/components'
 *
 * defineProps<{ active?: boolean }>()
 *
 * // Important: disable inheritance of attributes
 * defineOptions({ inheritAttrs: false })
 *
 * const { cx } = useBindCx()
 *
 * const variants = cva({
 *   base: 'border rounded p-2 bg-b-1',
 *   variants: { active: { true: 'bg-b-2' } },
 * })
 * </script>
 * <template>
 *   <div v-bind="cx(variants({ active }))">MockComponent</div>
 * </template>
 * ```
 */
declare const meta: {
    tags: string[];
    argTypes: {
        active: {
            control: "boolean";
            description: string;
        };
        class: {
            control: "text";
            description: string;
        };
        attrs: {
            control: "object";
            description: string;
        };
    };
    render: (args: import("@storybook/vue3").Args) => {
        components: {
            MockComponent: import("vue").DefineComponent<import("vue").ExtractPropTypes<{
                active: {
                    type: BooleanConstructor;
                    default: boolean;
                };
            }>, {
                cx: (...args: import("cva").CXOptions) => {
                    class: string;
                    [key: string]: any;
                };
                variants: (props?: ({
                    active?: boolean | undefined;
                } & ({
                    class?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                    className?: never;
                } | {
                    class?: never;
                    className?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                })) | undefined) => string;
            }, {}, {}, {}, import("vue").ComponentOptionsMixin, import("vue").ComponentOptionsMixin, {}, string, import("vue").PublicProps, Readonly<import("vue").ExtractPropTypes<{
                active: {
                    type: BooleanConstructor;
                    default: boolean;
                };
            }>> & Readonly<{}>, {
                active: boolean;
            }, {}, {}, {}, string, import("vue").ComponentProvideOptions, true, {}, any>;
        };
        setup(this: void): {
            bind: import("vue").ComputedRef<any>;
            passedIn: import("vue").ComputedRef<string>;
            rendered: import("vue").Ref<string, string>;
            mock: import("vue").Ref<import("vue").CreateComponentPublicInstanceWithMixins<Readonly<import("vue").ExtractPropTypes<{
                active: {
                    type: BooleanConstructor;
                    default: boolean;
                };
            }>> & Readonly<{}>, {
                cx: (...args: import("cva").CXOptions) => {
                    class: string;
                    [key: string]: any;
                };
                variants: (props?: ({
                    active?: boolean | undefined;
                } & ({
                    class?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                    className?: never;
                } | {
                    class?: never;
                    className?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                })) | undefined) => string;
            }, {}, {}, {}, import("vue").ComponentOptionsMixin, import("vue").ComponentOptionsMixin, {}, import("vue").PublicProps, {
                active: boolean;
            }, true, {}, {}, import("vue").GlobalComponents, import("vue").GlobalDirectives, string, {}, any, import("vue").ComponentProvideOptions, {
                P: {};
                B: {};
                D: {};
                C: {};
                M: {};
                Defaults: {};
            }, Readonly<import("vue").ExtractPropTypes<{
                active: {
                    type: BooleanConstructor;
                    default: boolean;
                };
            }>> & Readonly<{}>, {
                cx: (...args: import("cva").CXOptions) => {
                    class: string;
                    [key: string]: any;
                };
                variants: (props?: ({
                    active?: boolean | undefined;
                } & ({
                    class?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                    className?: never;
                } | {
                    class?: never;
                    className?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                })) | undefined) => string;
            }, {}, {}, {}, {
                active: boolean;
            }> | undefined, import("vue").CreateComponentPublicInstanceWithMixins<Readonly<import("vue").ExtractPropTypes<{
                active: {
                    type: BooleanConstructor;
                    default: boolean;
                };
            }>> & Readonly<{}>, {
                cx: (...args: import("cva").CXOptions) => {
                    class: string;
                    [key: string]: any;
                };
                variants: (props?: ({
                    active?: boolean | undefined;
                } & ({
                    class?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                    className?: never;
                } | {
                    class?: never;
                    className?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                })) | undefined) => string;
            }, {}, {}, {}, import("vue").ComponentOptionsMixin, import("vue").ComponentOptionsMixin, {}, import("vue").PublicProps, {
                active: boolean;
            }, true, {}, {}, import("vue").GlobalComponents, import("vue").GlobalDirectives, string, {}, any, import("vue").ComponentProvideOptions, {
                P: {};
                B: {};
                D: {};
                C: {};
                M: {};
                Defaults: {};
            }, Readonly<import("vue").ExtractPropTypes<{
                active: {
                    type: BooleanConstructor;
                    default: boolean;
                };
            }>> & Readonly<{}>, {
                cx: (...args: import("cva").CXOptions) => {
                    class: string;
                    [key: string]: any;
                };
                variants: (props?: ({
                    active?: boolean | undefined;
                } & ({
                    class?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                    className?: never;
                } | {
                    class?: never;
                    className?: string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | (string | number | boolean | any | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined)[] | {
                        [x: string]: any;
                    } | null | undefined;
                })) | undefined) => string;
            }, {}, {}, {}, {
                active: boolean;
            }> | undefined>;
        };
        template: string;
    };
};
export default meta;
type Story = StoryObj<typeof meta>;
export declare const Base: Story;
//# sourceMappingURL=useBindCx.stories.d.ts.map