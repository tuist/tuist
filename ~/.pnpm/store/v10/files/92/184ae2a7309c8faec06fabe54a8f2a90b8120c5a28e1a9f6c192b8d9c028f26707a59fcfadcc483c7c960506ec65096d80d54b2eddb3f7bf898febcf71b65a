import { z } from 'zod';
import { nanoidSchema } from '../shared/utility.js';

const cookieSchema = z.object({
    uid: nanoidSchema.brand(),
    /**  Defines the cookie name and its value. A cookie definition begins with a name-value pair.  */
    name: z.string().default(''),
    value: z.string().default(''),
    /** Defines the host to which the cookie will be sent. */
    domain: z.string().optional(),
    /** Indicates the path that must exist in the requested URL for the browser to send the Cookie header. */
    path: z.string().optional(),
});

export { cookieSchema };
