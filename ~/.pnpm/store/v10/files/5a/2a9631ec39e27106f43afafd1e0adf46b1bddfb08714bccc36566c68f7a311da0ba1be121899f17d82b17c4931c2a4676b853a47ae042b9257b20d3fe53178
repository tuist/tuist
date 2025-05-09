import { z } from 'zod';
export declare const cookieSchema: z.ZodObject<{
    uid: z.ZodBranded<z.ZodDefault<z.ZodOptional<z.ZodString>>, "cookie">;
    /**  Defines the cookie name and its value. A cookie definition begins with a name-value pair.  */
    name: z.ZodDefault<z.ZodString>;
    value: z.ZodDefault<z.ZodString>;
    /** Defines the host to which the cookie will be sent. */
    domain: z.ZodOptional<z.ZodString>;
    /** Indicates the path that must exist in the requested URL for the browser to send the Cookie header. */
    path: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    value: string;
    uid: string & z.BRAND<"cookie">;
    name: string;
    path?: string | undefined;
    domain?: string | undefined;
}, {
    path?: string | undefined;
    value?: string | undefined;
    uid?: string | undefined;
    name?: string | undefined;
    domain?: string | undefined;
}>;
/**
 * Cookies
 *
 * @see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie
 */
export type Cookie = z.infer<typeof cookieSchema>;
//# sourceMappingURL=cookie.d.ts.map