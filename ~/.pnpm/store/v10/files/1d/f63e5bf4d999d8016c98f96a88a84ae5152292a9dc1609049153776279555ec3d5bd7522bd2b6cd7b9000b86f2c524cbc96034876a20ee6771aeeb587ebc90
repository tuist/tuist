import type { Operation } from '@scalar/types/legacy';
import type { ContentSchema } from '../types';
type PropertyObject = {
    required?: string[];
    properties: {
        [key: string]: {
            type: string;
            description?: string;
        };
    };
};
declare function formatProperty(key: string, obj: PropertyObject): string;
declare function recursiveLogger(obj: ContentSchema): string[];
declare function extractRequestBody(operation: Operation): string[] | boolean;
export { formatProperty, recursiveLogger, extractRequestBody };
//# sourceMappingURL=specHelpers.d.ts.map