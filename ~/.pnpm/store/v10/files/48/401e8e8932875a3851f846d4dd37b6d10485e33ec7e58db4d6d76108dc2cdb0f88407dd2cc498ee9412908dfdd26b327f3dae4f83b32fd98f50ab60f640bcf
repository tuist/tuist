import { MergeHead } from '@unhead/schema';
import { V as VueHeadClient, U as UseHeadInput, b as UseHeadOptions } from './shared/vue.fwis0K4Q.js';
import 'vue';

type VueHeadClientPollyFill<T extends MergeHead> = VueHeadClient<T> & {
    /**
     * @deprecated use `resolveTags`
     */
    headTags: VueHeadClient<T>['resolveTags'];
    /**
     * @deprecated use `push`
     */
    addEntry: VueHeadClient<T>['push'];
    /**
     * @deprecated use `push`
     */
    addHeadObjs: VueHeadClient<T>['push'];
    /**
     * @deprecated use `useHead`
     */
    addReactiveEntry: (input: UseHeadInput<T>, options?: UseHeadOptions) => (() => void);
    /**
     * @deprecated Use useHead API.
     */
    removeHeadObjs: () => void;
    /**
     * @deprecated Call hook `entries:resolve` or update an entry
     */
    updateDOM: () => void;
    /**
     * @deprecated Access unhead properties directly.
     */
    unhead: VueHeadClient<T>;
};
/**
 * @deprecated Will be removed in v2.
 */
declare function polyfillAsVueUseHead<T extends MergeHead>(head: VueHeadClient<T>): VueHeadClientPollyFill<T>;

export { type VueHeadClientPollyFill, polyfillAsVueUseHead };
