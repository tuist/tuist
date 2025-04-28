import type { StoreContext } from '../store/store-context';
import { type Collection, type Server, type ServerPayload } from '@scalar/oas-utils/entities/spec';
/** Create storage objects for servers */
export declare function createStoreServers(useLocalStorage: boolean): {
    servers: Record<string, {
        uid: string & import("zod").BRAND<"server">;
        url: string;
        description?: string | undefined;
        variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
            enum?: [string, ...string[]];
            value?: string;
        }> | undefined;
    }>;
    serverMutators: {
        add: (item: {
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }) => void;
        delete: (uid: (string & import("zod").BRAND<"server">) | null | undefined) => void;
        set: (item: {
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }) => void;
        edit: <P extends "description" | "uid" | "url" | "variables" | `variables.${string}`>(uid: (string & import("zod").BRAND<"server">) | null | undefined, path: P, value: P extends "description" | "uid" | "url" | "variables" ? {
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }[P] : P extends `${infer K}.${infer R}` ? K extends "description" | "uid" | "url" | "variables" ? R extends import("@scalar/object-utils/nested").Path<{
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }[K]> ? import("@scalar/object-utils/nested").PathValue<{
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }[K], R> : never : K extends `${number}` ? never : never : P extends `${number}` ? never : never) => void;
        untrackedEdit: <P extends "description" | "uid" | "url" | "variables" | `variables.${string}`>(uid: string & import("zod").BRAND<"server">, path: P, value: P extends "description" | "uid" | "url" | "variables" ? {
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }[P] : P extends `${infer K}.${infer R}` ? K extends "description" | "uid" | "url" | "variables" ? R extends import("@scalar/object-utils/nested").Path<{
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }[K]> ? import("@scalar/object-utils/nested").PathValue<{
            uid: string & import("zod").BRAND<"server">;
            url: string;
            description?: string | undefined;
            variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
                enum?: [string, ...string[]];
                value?: string;
            }> | undefined;
        }[K], R> : never : K extends `${number}` ? never : never : P extends `${number}` ? never : never) => void;
        undo: (uid: string & import("zod").BRAND<"server">) => void;
        redo: (uid: string & import("zod").BRAND<"server">) => void;
        reset: () => void;
    };
};
/** Extended mutators and data for servers */
export declare function extendedServerDataFactory({ serverMutators, collections, collectionMutators, requests, requestMutators, }: StoreContext): {
    addServer: (payload: ServerPayload, parentUid: string) => {
        uid: string & import("zod").BRAND<"server">;
        url: string;
        description?: string | undefined;
        variables?: Record<string, Omit<import("@scalar/openapi-types").OpenAPIV3_1.ServerVariableObject, "enum"> & {
            enum?: [string, ...string[]];
            value?: string;
        }> | undefined;
    };
    deleteServer: (serverUid: Server["uid"], collectionUid: Collection["uid"]) => void;
};
//# sourceMappingURL=servers.d.ts.map