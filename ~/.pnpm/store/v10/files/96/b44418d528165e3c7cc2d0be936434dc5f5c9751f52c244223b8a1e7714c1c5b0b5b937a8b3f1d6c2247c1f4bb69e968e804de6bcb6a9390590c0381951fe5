import { z } from 'zod';

const xScalarSecretVarSchema = z.object({
    description: z.string().optional(),
    example: z.string().optional(),
});
const xScalarSecretsSchema = z.record(z.string(), xScalarSecretVarSchema);

export { xScalarSecretVarSchema, xScalarSecretsSchema };
