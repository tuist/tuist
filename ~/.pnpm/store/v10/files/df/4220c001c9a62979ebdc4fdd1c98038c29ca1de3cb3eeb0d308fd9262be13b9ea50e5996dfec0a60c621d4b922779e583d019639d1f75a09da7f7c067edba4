import type { OpenAPIV3_1 } from '@scalar/openapi-types';
import { type ZodSchema, z } from 'zod';
/**
 * Server Variable Object
 *
 * An object representing a Server Variable for server URL template substitution.
 *
 * @see https://github.com/OAI/OpenAPI-Specification/blob/main/versions/3.1.1.md#server-variable-object
 */
export declare const oasServerVariableSchema: z.ZodObject<{
    /**
     * An enumeration of string values to be used if the substitution options are from a limited set. The array MUST NOT be empty.
     */
    enum: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
    /**
     * REQUIRED. The default value to use for substitution, which SHALL be sent if an alternate value is not supplied.
     * Note this behavior is different than the Schema Object's treatment of default values, because in those cases
     * parameter values are optional. If the enum is defined, the value MUST exist in the enum's values.
     */
    default: z.ZodOptional<z.ZodString>;
    /**
     * An optional description for the server variable. CommonMark syntax MAY be used for rich text representation.
     */
    description: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    default?: string | undefined;
    description?: string | undefined;
    enum?: string[] | undefined;
}, {
    default?: string | undefined;
    description?: string | undefined;
    enum?: string[] | undefined;
}>;
/**
 * Server Object
 *
 * An object representing a Server.
 *
 * @see https://github.com/OAI/OpenAPI-Specification/blob/main/versions/3.1.1.md#server-object
 */
export declare const oasServerSchema: z.ZodObject<{
    /**
     * REQUIRED. A URL to the target host. This URL supports Server Variables and MAY be relative, to indicate that
     * the host location is relative to the location where the OpenAPI document is being served. Variable substitutions
     * will be made when a variable is named in {brackets}.
     */
    url: z.ZodString;
    /**
     * An optional string describing the host designated by the URL. CommonMark syntax MAY be used for rich text
     * representation.
     */
    description: z.ZodOptional<z.ZodString>;
    /** A map between a variable name and its value. The value is used for substitution in the server's URL template. */
    variables: z.ZodOptional<z.ZodRecord<z.ZodString, ZodSchema<Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }, z.ZodTypeDef, Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }>>>;
}, "strip", z.ZodTypeAny, {
    url: string;
    description?: string | undefined;
    variables?: Record<string, Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }> | undefined;
}, {
    url: string;
    description?: string | undefined;
    variables?: Record<string, Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }> | undefined;
}>;
export declare const serverSchema: z.ZodObject<z.objectUtil.extendShape<{
    /**
     * REQUIRED. A URL to the target host. This URL supports Server Variables and MAY be relative, to indicate that
     * the host location is relative to the location where the OpenAPI document is being served. Variable substitutions
     * will be made when a variable is named in {brackets}.
     */
    url: z.ZodString;
    /**
     * An optional string describing the host designated by the URL. CommonMark syntax MAY be used for rich text
     * representation.
     */
    description: z.ZodOptional<z.ZodString>;
    /** A map between a variable name and its value. The value is used for substitution in the server's URL template. */
    variables: z.ZodOptional<z.ZodRecord<z.ZodString, ZodSchema<Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }, z.ZodTypeDef, Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }>>>;
}, {
    uid: z.ZodBranded<z.ZodDefault<z.ZodOptional<z.ZodString>>, "server">;
}>, "strip", z.ZodTypeAny, {
    uid: string & z.BRAND<"server">;
    url: string;
    description?: string | undefined;
    variables?: Record<string, Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }> | undefined;
}, {
    url: string;
    uid?: string | undefined;
    description?: string | undefined;
    variables?: Record<string, Omit<OpenAPIV3_1.ServerVariableObject, "enum"> & {
        enum?: [string, ...string[]];
        value?: string;
    }> | undefined;
}>;
export type Server = z.infer<typeof serverSchema>;
export type ServerPayload = z.input<typeof serverSchema>;
//# sourceMappingURL=server.d.ts.map