import { z } from 'zod';
export type XScalarEnvVar = z.infer<typeof xScalarEnvVarSchema>;
export declare const xScalarEnvVarSchema: z.ZodUnion<[z.ZodObject<{
    description: z.ZodOptional<z.ZodString>;
    default: z.ZodDefault<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    default: string;
    description?: string | undefined;
}, {
    default?: string | undefined;
    description?: string | undefined;
}>, z.ZodString]>;
export declare const xScalarEnvironmentSchema: z.ZodObject<{
    description: z.ZodOptional<z.ZodString>;
    color: z.ZodOptional<z.ZodString>;
    /** A map of variables by name */
    variables: z.ZodRecord<z.ZodString, z.ZodUnion<[z.ZodObject<{
        description: z.ZodOptional<z.ZodString>;
        default: z.ZodDefault<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        default: string;
        description?: string | undefined;
    }, {
        default?: string | undefined;
        description?: string | undefined;
    }>, z.ZodString]>>;
}, "strip", z.ZodTypeAny, {
    variables: Record<string, string | {
        default: string;
        description?: string | undefined;
    }>;
    description?: string | undefined;
    color?: string | undefined;
}, {
    variables: Record<string, string | {
        default?: string | undefined;
        description?: string | undefined;
    }>;
    description?: string | undefined;
    color?: string | undefined;
}>;
/** A map of environments by name */
export declare const xScalarEnvironmentsSchema: z.ZodRecord<z.ZodString, z.ZodObject<{
    description: z.ZodOptional<z.ZodString>;
    color: z.ZodOptional<z.ZodString>;
    /** A map of variables by name */
    variables: z.ZodRecord<z.ZodString, z.ZodUnion<[z.ZodObject<{
        description: z.ZodOptional<z.ZodString>;
        default: z.ZodDefault<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        default: string;
        description?: string | undefined;
    }, {
        default?: string | undefined;
        description?: string | undefined;
    }>, z.ZodString]>>;
}, "strip", z.ZodTypeAny, {
    variables: Record<string, string | {
        default: string;
        description?: string | undefined;
    }>;
    description?: string | undefined;
    color?: string | undefined;
}, {
    variables: Record<string, string | {
        default?: string | undefined;
        description?: string | undefined;
    }>;
    description?: string | undefined;
    color?: string | undefined;
}>>;
export type XScalarEnvironment = z.infer<typeof xScalarEnvironmentSchema>;
export type XScalarEnvironments = z.infer<typeof xScalarEnvironmentsSchema>;
//# sourceMappingURL=x-scalar-environments.d.ts.map