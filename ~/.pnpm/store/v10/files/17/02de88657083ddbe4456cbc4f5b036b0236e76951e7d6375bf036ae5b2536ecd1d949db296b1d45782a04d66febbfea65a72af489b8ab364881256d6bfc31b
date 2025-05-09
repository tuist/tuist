import { nanoid } from 'nanoid';
import { z } from 'zod';

/** Generates a default value */
const nanoidSchema = z
    .string()
    .min(7)
    .optional()
    .default(() => nanoid());
/** Schema for selectedSecuritySchemeUids */
const selectedSecuritySchemeUidSchema = z
    .union([
    z.string().brand(),
    z.string().brand().array(),
])
    .array()
    .default([]);

export { nanoidSchema, selectedSecuritySchemeUidSchema };
