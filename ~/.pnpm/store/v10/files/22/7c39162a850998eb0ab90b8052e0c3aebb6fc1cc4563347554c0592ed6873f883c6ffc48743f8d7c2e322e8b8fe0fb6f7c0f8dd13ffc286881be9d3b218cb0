import { z } from 'zod';
/** Generates a default value */
export declare const nanoidSchema: z.ZodDefault<z.ZodOptional<z.ZodString>>;
/** UID format for objects */
export type Nanoid = z.infer<typeof nanoidSchema>;
/** All of our Zod brands for entities, used to brand nanoidSchemas. */
export type ENTITY_BRANDS = {
    COLLECTION: 'collection';
    COOKIE: 'cookie';
    ENVIRONMENT: 'environment';
    EXAMPLE: 'example';
    OPERATION: 'operation';
    SECURITY_SCHEME: 'securityScheme';
    SERVER: 'server';
    TAG: 'tag';
    WORKSPACE: 'workspace';
};
/** Schema for selectedSecuritySchemeUids */
export declare const selectedSecuritySchemeUidSchema: z.ZodDefault<z.ZodArray<z.ZodUnion<[z.ZodBranded<z.ZodString, "securityScheme">, z.ZodArray<z.ZodBranded<z.ZodString, "securityScheme">, "many">]>, "many">>;
export type SelectedSecuritySchemeUids = z.infer<typeof selectedSecuritySchemeUidSchema>;
//# sourceMappingURL=utility.d.ts.map