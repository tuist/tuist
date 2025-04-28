import * as _zag_js_anatomy from '@zag-js/anatomy';
import { CommonProperties, DirectionProperty, PropTypes, NormalizeProps } from '@zag-js/types';
import * as _zag_js_core from '@zag-js/core';
import { Machine, Service } from '@zag-js/core';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"root" | "image" | "fallback">;

type LoadStatus = "error" | "loaded";
interface StatusChangeDetails {
    status: LoadStatus;
}
type ElementIds = Partial<{
    root: string;
    image: string;
    fallback: string;
}>;
interface AvatarProps extends CommonProperties, DirectionProperty {
    /**
     * Functional called when the image loading status changes.
     */
    onStatusChange?: ((details: StatusChangeDetails) => void) | undefined;
    /**
     * The ids of the elements in the avatar. Useful for composition.
     */
    ids?: ElementIds | undefined;
}
interface AvatarSchema {
    props: AvatarProps;
    context: any;
    initial: "loading";
    effect: "trackImageRemoval" | "trackSrcChange";
    action: "invokeOnLoad" | "invokeOnError" | "checkImageStatus";
    event: {
        type: "img.loaded";
        src?: string;
    } | {
        type: "img.error";
        src?: string;
    } | {
        type: "img.unmount";
    } | {
        type: "src.change";
    };
    state: "loading" | "error" | "loaded";
}
type AvatarService = Service<AvatarSchema>;
type AvatarMachine = Machine<AvatarSchema>;
interface AvatarApi<T extends PropTypes = PropTypes> {
    /**
     * Whether the image is loaded.
     */
    loaded: boolean;
    /**
     * Function to set new src.
     */
    setSrc(src: string): void;
    /**
     * Function to set loaded state.
     */
    setLoaded(): void;
    /**
     * Function to set error state.
     */
    setError(): void;
    getRootProps(): T["element"];
    getImageProps(): T["img"];
    getFallbackProps(): T["element"];
}

declare function connect<T extends PropTypes>(service: Service<AvatarSchema>, normalize: NormalizeProps<T>): AvatarApi<T>;

declare const machine: _zag_js_core.Machine<AvatarSchema>;

declare const props: (keyof AvatarProps)[];
declare const splitProps: <Props extends Partial<AvatarProps>>(props: Props) => [Partial<AvatarProps>, Omit<Props, keyof AvatarProps>];

export { type AvatarApi as Api, type ElementIds, type LoadStatus, type AvatarMachine as Machine, type AvatarProps as Props, type AvatarService as Service, type StatusChangeDetails, anatomy, connect, machine, props, splitProps };
