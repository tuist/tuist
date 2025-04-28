/**
 * @param providerComponentName - The name(s) of the component(s) providing the context.
 *
 * There are situations where context can come from multiple components. In such cases, you might need to give an array of component names to provide your context, instead of just a single string.
 *
 * @param contextName The description for injection key symbol.
 */
export declare function createContext<ContextValue>(providerComponentName: string | string[], contextName?: string): readonly [<T extends ContextValue | null | undefined = ContextValue>(fallback?: T) => T extends null ? ContextValue | null : ContextValue, (contextValue: ContextValue) => ContextValue];
