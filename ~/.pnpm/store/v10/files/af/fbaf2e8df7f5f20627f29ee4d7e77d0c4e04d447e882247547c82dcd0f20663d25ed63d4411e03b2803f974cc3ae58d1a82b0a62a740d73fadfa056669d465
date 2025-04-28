import type { OpenAPIV3_1 } from '@scalar/openapi-types';
import type { UnknownObject } from '@scalar/types/utils';
/**
 * Upgrade from OpenAPI 3.0.x to 3.1.1
 *
 * https://www.openapis.org/blog/2021/02/16/migrating-from-openapi-3-0-to-3-1-0
 */
export declare function upgradeFromThreeToThreeOne(originalSpecification: UnknownObject): (Omit<Omit<import("@scalar/openapi-types").OpenAPIV3.Document<{}>, "paths" | "components">, keyof {
    [customExtension: `x-${string}`]: any;
    [key: string]: any;
}> & {
    openapi?: "3.1.0" | "3.1.1";
    swagger?: undefined;
    info?: OpenAPIV3_1.InfoObject;
    jsonSchemaDialect?: string;
    servers?: OpenAPIV3_1.ServerObject[];
} & Pick<{
    paths?: OpenAPIV3_1.PathsObject<{}, {}>;
    webhooks?: Record<string, OpenAPIV3_1.PathItemObject | OpenAPIV3_1.ReferenceObject>;
    components?: OpenAPIV3_1.ComponentsObject;
}, "paths"> & Omit<Partial<{
    paths?: OpenAPIV3_1.PathsObject<{}, {}>;
    webhooks?: Record<string, OpenAPIV3_1.PathItemObject | OpenAPIV3_1.ReferenceObject>;
    components?: OpenAPIV3_1.ComponentsObject;
}>, "paths"> & {
    [customExtension: `x-${string}`]: any;
    [key: string]: any;
}) | UnknownObject;
/** Determine if the current path is within a schema */
export declare function isSchemaPath(path: string[]): boolean;
//# sourceMappingURL=upgradeFromThreeToThreeOne.d.ts.map