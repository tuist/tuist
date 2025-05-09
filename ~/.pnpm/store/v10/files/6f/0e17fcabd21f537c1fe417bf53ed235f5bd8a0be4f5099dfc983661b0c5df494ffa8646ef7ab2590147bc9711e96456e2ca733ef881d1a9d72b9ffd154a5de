import { z } from 'zod';
import { nanoidSchema } from '../shared/utility.js';

const environmentSchema = z.object({
    uid: nanoidSchema.brand(),
    name: z.string().optional().default('Default Environment'),
    color: z.string().optional().default('#0082D0'),
    value: z.string().default(''),
    isDefault: z.boolean().optional(),
});

export { environmentSchema };
