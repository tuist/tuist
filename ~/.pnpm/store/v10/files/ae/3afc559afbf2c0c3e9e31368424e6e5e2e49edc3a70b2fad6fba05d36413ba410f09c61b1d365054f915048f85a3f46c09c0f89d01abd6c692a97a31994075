import { AxiosResponse, AxiosRequestConfig, AxiosInstance } from 'axios';
import { ShallowRef, Ref } from 'vue-demi';

interface UseAxiosReturn<T, R = AxiosResponse<T>, _D = any> {
    /**
     * Axios Response
     */
    response: ShallowRef<R | undefined>;
    /**
     * Axios response data
     */
    data: Ref<T | undefined>;
    /**
     * Indicates if the request has finished
     */
    isFinished: Ref<boolean>;
    /**
     * Indicates if the request is currently loading
     */
    isLoading: Ref<boolean>;
    /**
     * Indicates if the request was canceled
     */
    isAborted: Ref<boolean>;
    /**
     * Any errors that may have occurred
     */
    error: ShallowRef<unknown | undefined>;
    /**
     * Aborts the current request
     */
    abort: (message?: string | undefined) => void;
    /**
     * Alias to `abort`
     */
    cancel: (message?: string | undefined) => void;
    /**
     * Alias to `isAborted`
     */
    isCanceled: Ref<boolean>;
}
interface StrictUseAxiosReturn<T, R, D> extends UseAxiosReturn<T, R, D> {
    /**
     * Manually call the axios request
     */
    execute: (url?: string | AxiosRequestConfig<D>, config?: AxiosRequestConfig<D>) => Promise<StrictUseAxiosReturn<T, R, D>>;
}
interface EasyUseAxiosReturn<T, R, D> extends UseAxiosReturn<T, R, D> {
    /**
     * Manually call the axios request
     */
    execute: (url: string, config?: AxiosRequestConfig<D>) => Promise<EasyUseAxiosReturn<T, R, D>>;
}
interface UseAxiosOptions<T = any> {
    /**
     * Will automatically run axios request when `useAxios` is used
     *
     */
    immediate?: boolean;
    /**
     * Use shallowRef.
     *
     * @default true
     */
    shallow?: boolean;
    /**
     * Abort previous request when a new request is made.
     *
     * @default true
     */
    abortPrevious?: boolean;
    /**
     * Callback when error is caught.
     */
    onError?: (e: unknown) => void;
    /**
     * Callback when success is caught.
     */
    onSuccess?: (data: T) => void;
    /**
     * Initial data to use
     */
    initialData?: T;
    /**
     * Sets the state to initialState before executing the promise.
     */
    resetOnExecute?: boolean;
    /**
     * Callback when request is finished.
     */
    onFinish?: () => void;
}
declare function useAxios<T = any, R = AxiosResponse<T>, D = any>(url: string, config?: AxiosRequestConfig<D>, options?: UseAxiosOptions): StrictUseAxiosReturn<T, R, D> & Promise<StrictUseAxiosReturn<T, R, D>>;
declare function useAxios<T = any, R = AxiosResponse<T>, D = any>(url: string, instance?: AxiosInstance, options?: UseAxiosOptions): StrictUseAxiosReturn<T, R, D> & Promise<StrictUseAxiosReturn<T, R, D>>;
declare function useAxios<T = any, R = AxiosResponse<T>, D = any>(url: string, config: AxiosRequestConfig<D>, instance: AxiosInstance, options?: UseAxiosOptions): StrictUseAxiosReturn<T, R, D> & Promise<StrictUseAxiosReturn<T, R, D>>;
declare function useAxios<T = any, R = AxiosResponse<T>, D = any>(config?: AxiosRequestConfig<D>): EasyUseAxiosReturn<T, R, D> & Promise<EasyUseAxiosReturn<T, R, D>>;
declare function useAxios<T = any, R = AxiosResponse<T>, D = any>(instance?: AxiosInstance): EasyUseAxiosReturn<T, R, D> & Promise<EasyUseAxiosReturn<T, R, D>>;
declare function useAxios<T = any, R = AxiosResponse<T>, D = any>(config?: AxiosRequestConfig<D>, instance?: AxiosInstance): EasyUseAxiosReturn<T, R, D> & Promise<EasyUseAxiosReturn<T, R, D>>;

export { type EasyUseAxiosReturn, type StrictUseAxiosReturn, type UseAxiosOptions, type UseAxiosReturn, useAxios };
