import type { FilterResult, Queue, Task } from '../../../types/index.ts';
import type { DereferenceOptions } from '../../dereference.ts';
import type { FilterCallback } from '../../filter.ts';
declare global {
    interface Commands {
        filter: {
            task: {
                name: 'filter';
                options?: FilterCallback;
            };
            result: FilterResult;
        };
    }
}
/**
 * Filter the given OpenAPI document
 */
export declare function filterCommand<T extends Task[]>(previousQueue: Queue<T>, options?: FilterCallback): {
    dereference: (dereferenceOptions?: DereferenceOptions) => {
        details: () => Promise<import("../../../types/index.ts").DetailsResult>;
        files: () => Promise<import("../../../types/index.ts").Filesystem>;
        get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
            name: "filter";
            options?: FilterCallback;
        }, {
            name: "dereference";
            options?: DereferenceOptions;
        }]>>;
        toJson: () => Promise<string>;
        toYaml: () => Promise<string>;
    };
    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
    files: () => Promise<import("../../../types/index.ts").Filesystem>;
    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
        name: "filter";
        options?: FilterCallback;
    }]>>;
    toJson: () => Promise<string>;
    toYaml: () => Promise<string>;
};
//# sourceMappingURL=filterCommand.d.ts.map