import { z } from 'zod';
export declare const environmentSchema: z.ZodObject<{
    uid: z.ZodBranded<z.ZodDefault<z.ZodOptional<z.ZodString>>, "environment">;
    name: z.ZodDefault<z.ZodOptional<z.ZodString>>;
    color: z.ZodDefault<z.ZodOptional<z.ZodString>>;
    value: z.ZodDefault<z.ZodString>;
    isDefault: z.ZodOptional<z.ZodBoolean>;
}, "strip", z.ZodTypeAny, {
    value: string;
    uid: string & z.BRAND<"environment">;
    name: string;
    color: string;
    isDefault?: boolean | undefined;
}, {
    value?: string | undefined;
    uid?: string | undefined;
    name?: string | undefined;
    color?: string | undefined;
    isDefault?: boolean | undefined;
}>;
/** Environment */
export type Environment = z.infer<typeof environmentSchema>;
export type EnvironmentPayload = z.input<typeof environmentSchema>;
//# sourceMappingURL=environment.d.ts.map