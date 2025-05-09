import type { Component } from 'vue';
import { ComponentOptionsMixin } from 'vue';
import { ComponentProvideOptions } from 'vue';
import { CSSProperties } from 'vue';
import { DefineComponent } from 'vue';
import type { Plugin as Plugin_2 } from 'vue';
import { PublicProps } from 'vue';
import { Ref } from 'vue';

export declare interface Action {
    label: Component | string;
    onClick: (event: MouseEvent) => void;
    actionButtonStyle?: CSSProperties;
}

declare type CnFunction = (...classes: Array<string | undefined>) => string;

export declare type ExternalToast<T extends Component = Component> = Omit<ToastT<T>, 'id' | 'type' | 'title' | 'promise' | 'delete'> & {
    id?: number | string;
};

declare const plugin: Plugin_2;
export default plugin;

declare type Position = 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right' | 'top-center' | 'bottom-center';

declare type PromiseData<ToastData = any> = ExternalToast & {
    loading?: string | Component;
    success?: PromiseTResult<ToastData>;
    error?: PromiseTResult;
    description?: PromiseTResult;
    finally?: () => void | Promise<void>;
};

declare type PromiseT<Data = any> = Promise<Data> | (() => Promise<Data>);

declare type PromiseTResult<Data = any> = string | Component | ((data: Data) => Component | string | Promise<Component | string>);

declare type Theme = 'light' | 'dark' | 'system';

declare type titleT = (() => string | Component) | string | Component;

export declare const toast: typeof toastFunction & {
    success: (message: titleT, data?: ExternalToast) => string | number;
    info: (message: titleT, data?: ExternalToast) => string | number;
    warning: (message: titleT, data?: ExternalToast) => string | number;
    error: (message: titleT, data?: ExternalToast) => string | number;
    custom: (component: Component, data?: ExternalToast) => string | number;
    message: (message: titleT, data?: ExternalToast) => string | number;
    promise: <ToastData>(promise: PromiseT<ToastData>, data?: PromiseData<ToastData> | undefined) => (string & {
        unwrap: () => Promise<ToastData>;
    }) | (number & {
        unwrap: () => Promise<ToastData>;
    }) | {
        unwrap: () => Promise<ToastData>;
    } | undefined;
    dismiss: (id?: number | string) => string | number | undefined;
    loading: (message: titleT, data?: ExternalToast) => string | number;
} & {
    getHistory: () => (ToastT<Component> | ToastToDismiss)[];
};

export declare interface ToastClasses {
    toast?: string;
    title?: string;
    description?: string;
    loader?: string;
    closeButton?: string;
    cancelButton?: string;
    actionButton?: string;
    success?: string;
    error?: string;
    info?: string;
    warning?: string;
    loading?: string;
    default?: string;
    content?: string;
    icon?: string;
}

export declare const Toaster: DefineComponent<ToasterProps, {}, {}, {}, {}, ComponentOptionsMixin, ComponentOptionsMixin, {}, string, PublicProps, Readonly<ToasterProps> & Readonly<{}>, {
richColors: boolean;
invert: boolean;
closeButton: boolean;
style: CSSProperties;
class: string;
position: Position;
gap: number;
offset: string | number;
visibleToasts: number;
pauseWhenPageIsHidden: boolean;
cn: CnFunction;
theme: Theme;
hotkey: string[];
expand: boolean;
toastOptions: ToastOptions;
dir: "rtl" | "ltr" | "auto";
containerAriaLabel: string;
}, {}, {}, {}, string, ComponentProvideOptions, false, {}, any>;

export declare interface ToasterProps {
    invert?: boolean;
    theme?: Theme;
    position?: Position;
    hotkey?: string[];
    richColors?: boolean;
    expand?: boolean;
    duration?: number;
    gap?: number;
    visibleToasts?: number;
    closeButton?: boolean;
    toastOptions?: ToastOptions;
    class?: string;
    style?: CSSProperties;
    offset?: string | number;
    dir?: 'rtl' | 'ltr' | 'auto';
    icons?: ToastIcons;
    containerAriaLabel?: string;
    pauseWhenPageIsHidden?: boolean;
    cn?: CnFunction;
}

declare function toastFunction(message: titleT, data?: ExternalToast): string | number;

declare interface ToastIcons {
    success?: Component;
    info?: Component;
    warning?: Component;
    error?: Component;
    loading?: Component;
    close?: Component;
}

declare interface ToastOptions {
    class?: string;
    closeButton?: boolean;
    descriptionClass?: string;
    style?: CSSProperties;
    cancelButtonStyle?: CSSProperties;
    actionButtonStyle?: CSSProperties;
    duration?: number;
    unstyled?: boolean;
    classes?: ToastClasses;
}

export declare interface ToastT<T extends Component = Component> {
    id: number | string;
    title?: (() => string | Component) | string | Component;
    type?: ToastTypes;
    icon?: Component;
    component?: T;
    componentProps?: any;
    richColors?: boolean;
    invert?: boolean;
    closeButton?: boolean;
    dismissible?: boolean;
    description?: (() => string | Component) | string | Component;
    duration?: number;
    delete?: boolean;
    important?: boolean;
    action?: Action | Component;
    cancel?: Action | Component;
    onDismiss?: (toast: ToastT) => void;
    onAutoClose?: (toast: ToastT) => void;
    promise?: PromiseT;
    cancelButtonStyle?: CSSProperties;
    actionButtonStyle?: CSSProperties;
    style?: CSSProperties;
    unstyled?: boolean;
    class?: string;
    classes?: ToastClasses;
    descriptionClass?: string;
    position?: Position;
}

export declare interface ToastToDismiss {
    id: number | string;
    dismiss: boolean;
}

declare type ToastTypes = 'normal' | 'action' | 'success' | 'info' | 'warning' | 'error' | 'loading' | 'default';

export declare function useVueSonner(): {
    activeToasts: Ref<ToastT[]>;
};

export { }
