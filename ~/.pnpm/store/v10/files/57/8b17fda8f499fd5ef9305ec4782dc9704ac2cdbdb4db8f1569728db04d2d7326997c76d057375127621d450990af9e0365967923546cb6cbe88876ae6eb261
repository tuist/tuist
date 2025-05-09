import { type RequestMethod } from '../entities/spec/requests.js';
/**
 * HTTP methods in a specific order
 * Do not change the order
 */
export declare const REQUEST_METHODS: {
    [x in RequestMethod]: {
        short: string;
        color: string;
        backgroundColor: string;
    };
};
/** HTTP Methods which can have a body */
declare const BODY_METHODS: readonly ["post", "put", "patch", "delete"];
type BodyMethod = (typeof BODY_METHODS)[number];
/** Makes a check to see if this method CAN have a body */
export declare const canMethodHaveBody: (method: RequestMethod) => method is BodyMethod;
/**
 * Accepts an HTTP Method name and returns some properties for the tag
 */
export declare const getHttpMethodInfo: (methodName: string) => {
    short: string;
    color: string;
    backgroundColor: string;
};
/** Type guard which takes in a string and returns true if it is in fact an HTTPMethod */
export declare const isHttpMethod: (method?: string | undefined) => method is RequestMethod;
export {};
//# sourceMappingURL=httpMethods.d.ts.map