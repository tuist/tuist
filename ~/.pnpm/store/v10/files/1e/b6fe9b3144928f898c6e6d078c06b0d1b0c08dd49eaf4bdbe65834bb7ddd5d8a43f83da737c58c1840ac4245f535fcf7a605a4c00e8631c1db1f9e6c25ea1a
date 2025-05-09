import type { DereferenceResult, Queue, Task } from '../../../types/index.ts';
import type { DereferenceOptions } from '../../dereference.ts';
declare global {
    interface Commands {
        dereference: {
            task: {
                name: 'dereference';
                options?: DereferenceOptions;
            };
            result: DereferenceResult;
        };
    }
}
/**
 * Dereference the given OpenAPI document
 */
export declare function dereferenceCommand<T extends Task[]>(previousQueue: Queue<T>, options?: DereferenceOptions): {
    details: () => Promise<import("../../../types/index.ts").DetailsResult>;
    files: () => Promise<import("../../../types/index.ts").Filesystem>;
    get: () => Promise<import("../../../types/index.ts").CommandChain<[...T, {
        name: "dereference";
        options?: DereferenceOptions;
    }]>>;
    toJson: () => Promise<string>;
    toYaml: () => Promise<string>;
};
//# sourceMappingURL=dereferenceCommand.d.ts.map