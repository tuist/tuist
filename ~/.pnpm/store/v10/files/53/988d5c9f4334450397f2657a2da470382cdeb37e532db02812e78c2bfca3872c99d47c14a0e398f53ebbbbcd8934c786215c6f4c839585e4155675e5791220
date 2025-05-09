import { z } from 'zod';

const xScalarEnvVarSchema = z.union([
    z.object({
        description: z.string().optional(),
        default: z.string().default(''),
    }),
    z.string(),
]);
const xScalarEnvironmentSchema = z.object({
    description: z.string().optional(),
    color: z.string().optional(),
    /** A map of variables by name */
    variables: z.record(z.string(), xScalarEnvVarSchema),
});
/** A map of environments by name */
const xScalarEnvironmentsSchema = z.record(
/** Name */
z.string(), 
/** Environment definition */
xScalarEnvironmentSchema);

export { xScalarEnvVarSchema, xScalarEnvironmentSchema, xScalarEnvironmentsSchema };
