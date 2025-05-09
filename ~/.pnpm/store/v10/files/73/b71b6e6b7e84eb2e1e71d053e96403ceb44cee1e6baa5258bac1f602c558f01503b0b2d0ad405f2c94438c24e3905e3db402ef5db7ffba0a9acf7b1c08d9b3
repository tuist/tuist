import type { StoreContext } from '../store/store-context';
import { type Collection, type Tag, type TagPayload } from '@scalar/oas-utils/entities/spec';
/** Create cookie mutators for the workspace */
export declare function createStoreTags(useLocalStorage: boolean): {
    tags: Record<string, {
        type: "tag";
        uid: string & import("zod").BRAND<"tag">;
        name: string;
        children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
        description?: string | undefined;
        externalDocs?: {
            url: string;
            description?: string | undefined;
        } | undefined;
        'x-scalar-children'?: {
            tagName: string;
        }[] | undefined;
        'x-internal'?: boolean | undefined;
        'x-scalar-ignore'?: boolean | undefined;
    }>;
    tagMutators: {
        add: (item: {
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }) => void;
        delete: (uid: (string & import("zod").BRAND<"tag">) | null | undefined) => void;
        set: (item: {
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }) => void;
        edit: <P extends "description" | "externalDocs" | "x-internal" | "x-scalar-ignore" | "type" | "name" | "uid" | "children" | "externalDocs.description" | "externalDocs.url" | `children.${number}` | "x-scalar-children" | `x-scalar-children.${number}` | `x-scalar-children.${number}.tagName`>(uid: (string & import("zod").BRAND<"tag">) | null | undefined, path: P, value: P extends "description" | "externalDocs" | "x-internal" | "x-scalar-ignore" | "type" | "name" | "uid" | "children" | "x-scalar-children" ? {
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }[P] : P extends `${infer K}.${infer R}` ? K extends "description" | "externalDocs" | "x-internal" | "x-scalar-ignore" | "type" | "name" | "uid" | "children" | "x-scalar-children" ? R extends import("@scalar/object-utils/nested").Path<{
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }[K]> ? import("@scalar/object-utils/nested").PathValue<{
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }[K], R> : never : K extends `${number}` ? never : never : P extends `${number}` ? never : never) => void;
        untrackedEdit: <P extends "description" | "externalDocs" | "x-internal" | "x-scalar-ignore" | "type" | "name" | "uid" | "children" | "externalDocs.description" | "externalDocs.url" | `children.${number}` | "x-scalar-children" | `x-scalar-children.${number}` | `x-scalar-children.${number}.tagName`>(uid: string & import("zod").BRAND<"tag">, path: P, value: P extends "description" | "externalDocs" | "x-internal" | "x-scalar-ignore" | "type" | "name" | "uid" | "children" | "x-scalar-children" ? {
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }[P] : P extends `${infer K}.${infer R}` ? K extends "description" | "externalDocs" | "x-internal" | "x-scalar-ignore" | "type" | "name" | "uid" | "children" | "x-scalar-children" ? R extends import("@scalar/object-utils/nested").Path<{
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }[K]> ? import("@scalar/object-utils/nested").PathValue<{
            type: "tag";
            uid: string & import("zod").BRAND<"tag">;
            name: string;
            children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
            description?: string | undefined;
            externalDocs?: {
                url: string;
                description?: string | undefined;
            } | undefined;
            'x-scalar-children'?: {
                tagName: string;
            }[] | undefined;
            'x-internal'?: boolean | undefined;
            'x-scalar-ignore'?: boolean | undefined;
        }[K], R> : never : K extends `${number}` ? never : never : P extends `${number}` ? never : never) => void;
        undo: (uid: string & import("zod").BRAND<"tag">) => void;
        redo: (uid: string & import("zod").BRAND<"tag">) => void;
        reset: () => void;
    };
};
/**
 * Create the extended mutators for tag with side effects
 * TODO:
 * - tag nesting, add/remove into another tag
 */
export declare function extendedTagDataFactory({ collectionMutators, collections, requests, requestMutators, tagMutators, }: StoreContext): {
    addTag: (payload: TagPayload, collectionUid: Collection["uid"]) => void | {
        type: "tag";
        uid: string & import("zod").BRAND<"tag">;
        name: string;
        children: ((string & import("zod").BRAND<"tag">) | (string & import("zod").BRAND<"operation">))[];
        description?: string | undefined;
        externalDocs?: {
            url: string;
            description?: string | undefined;
        } | undefined;
        'x-scalar-children'?: {
            tagName: string;
        }[] | undefined;
        'x-internal'?: boolean | undefined;
        'x-scalar-ignore'?: boolean | undefined;
    };
    deleteTag: (tag: Tag, collectionUid: Collection["uid"]) => void;
};
//# sourceMappingURL=tags.d.ts.map