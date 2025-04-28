export type ToastOptions = {
    timeout?: number;
    description?: string;
};
export type ToastFunction = (message: string, level?: 'warn' | 'info' | 'error', options?: ToastOptions) => void | null;
export declare function initializeToasts(toastFunction: ToastFunction): void;
/** Emit toasts */
export declare function useToasts(): {
    initializeToasts: typeof initializeToasts;
    toast: (message: string, level?: "warn" | "info" | "error", options?: ToastOptions) => void;
};
//# sourceMappingURL=useToasts.d.ts.map