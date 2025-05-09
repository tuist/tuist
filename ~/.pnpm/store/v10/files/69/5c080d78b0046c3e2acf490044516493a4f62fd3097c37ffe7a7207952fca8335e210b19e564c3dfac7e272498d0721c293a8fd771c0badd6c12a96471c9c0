/**
 * These types are copied from openapi-types, with two modifications:
 *
 * - all attributes are optional, you can’t rely on the specification for user input
 * - extensions (basically any attributes, not only prefixed with an `x-`) are allowed
 *
 * We deal with user input and can’t assume they really stick to any official specification.
 */
/** any other attribute, for example x-* extensions */
type AnyOtherAttribute = {
    /** OpenAPI extension */
    [customExtension: `x-${string}`]: any;
    /** Unknown attribute */
    [key: string]: any;
};
export declare namespace OpenAPI {
    type Document<T extends AnyOtherAttribute = {}> = OpenAPIV2.Document<T> | OpenAPIV3.Document<T> | OpenAPIV3_1.Document<T>;
    type Operation<T = {}> = OpenAPIV2.OperationObject<T> | OpenAPIV3.OperationObject<T> | OpenAPIV3_1.OperationObject<T>;
    type Request = {
        body?: any;
        headers?: object;
        params?: object;
        query?: object;
    };
    type ResponseObject = OpenAPIV2.ResponseObject | OpenAPIV3.ResponseObject | OpenAPIV3_1.ResponseObject;
    type HeaderObject = OpenAPIV2.HeaderObject | OpenAPIV3.HeaderObject | OpenAPIV3_1.HeaderObject;
    type Parameter = OpenAPIV3_1.ReferenceObject | OpenAPIV3_1.ParameterObject | OpenAPIV3.ReferenceObject | OpenAPIV3.ParameterObject | OpenAPIV2.ReferenceObject | OpenAPIV2.Parameter;
    type Parameters = (OpenAPIV3_1.ReferenceObject | OpenAPIV3_1.ParameterObject)[] | (OpenAPIV3.ReferenceObject | OpenAPIV3.ParameterObject)[] | (OpenAPIV2.ReferenceObject | OpenAPIV2.Parameter)[];
    type ExampleObject = OpenAPIV2.ExampleObject | OpenAPIV3.ExampleObject | OpenAPIV3_1.ExampleObject;
    type SchemaObject = OpenAPIV2.SchemaObject | OpenAPIV3.SchemaObject | OpenAPIV3_1.SchemaObject;
    type HttpMethod = keyof typeof OpenAPIV2.HttpMethods | keyof typeof OpenAPIV3.HttpMethods | OpenAPIV3_1.HttpMethods;
}
export declare namespace OpenAPIV3_1 {
    type Modify<T, R> = Omit<T, keyof R> & R;
    type PathsWebhooksComponents<T = {}> = {
        paths?: PathsObject<T>;
        webhooks?: Record<string, PathItemObject | ReferenceObject>;
        components?: ComponentsObject;
    };
    export type Document<T = {}> = Modify<Omit<OpenAPIV3.Document<T>, 'paths' | 'components'>, {
        /**
         * Version of the OpenAPI specification
         * @see https://github.com/OAI/OpenAPI-Specification/tree/main/versions
         */
        openapi?: '3.1.0' | '3.1.1';
        swagger?: undefined;
        info?: InfoObject;
        jsonSchemaDialect?: string;
        servers?: ServerObject[];
    } & ((Pick<PathsWebhooksComponents<T>, 'paths'> & Omit<Partial<PathsWebhooksComponents<T>>, 'paths'>) | (Pick<PathsWebhooksComponents<T>, 'webhooks'> & Omit<Partial<PathsWebhooksComponents<T>>, 'webhooks'>) | (Pick<PathsWebhooksComponents<T>, 'components'> & Omit<Partial<PathsWebhooksComponents<T>>, 'components'>)) & T & AnyOtherAttribute>;
    export type InfoObject = Modify<OpenAPIV3.InfoObject, {
        summary?: string;
        license?: LicenseObject;
    }>;
    export type ContactObject = OpenAPIV3.ContactObject;
    export type LicenseObject = Modify<OpenAPIV3.LicenseObject, {
        identifier?: string;
    }>;
    export type ServerObject = Modify<OpenAPIV3.ServerObject, {
        url?: string;
        description?: string;
        variables?: Record<string, ServerVariableObject>;
    }>;
    export type ServerVariableObject = Modify<OpenAPIV3.ServerVariableObject, {
        enum?: [string, ...string[]];
    }>;
    export type PathsObject<T = {}, P extends {} = {}> = Record<string, (PathItemObject<T> & P) | undefined>;
    export type HttpMethods = OpenAPIV3.HttpMethods;
    export type PathItemObject<T = {}> = Modify<OpenAPIV3.PathItemObject<T>, {
        servers?: ServerObject[];
        parameters?: (ReferenceObject | ParameterObject)[];
    }> & {
        [method in HttpMethods]?: OperationObject<T>;
    };
    export type OperationObject<T = {}> = Modify<OpenAPIV3.OperationObject<T>, {
        parameters?: (ReferenceObject | ParameterObject)[];
        requestBody?: ReferenceObject | RequestBodyObject;
        responses?: ResponsesObject;
        callbacks?: Record<string, ReferenceObject | CallbackObject>;
        servers?: ServerObject[];
    }> & T;
    export type ExternalDocumentationObject = OpenAPIV3.ExternalDocumentationObject;
    export type ParameterObject = OpenAPIV3.ParameterObject;
    export type HeaderObject = OpenAPIV3.HeaderObject;
    export type ParameterBaseObject = OpenAPIV3.ParameterBaseObject;
    export type NonArraySchemaObjectType = OpenAPIV3.NonArraySchemaObjectType | 'null';
    export type ArraySchemaObjectType = OpenAPIV3.ArraySchemaObjectType;
    /**
     * There is no way to tell typescript to require items when type is either 'array' or array containing 'array' type
     * 'items' will be always visible as optional
     * Casting schema object to ArraySchemaObject or NonArraySchemaObject will work fine
     */
    export type SchemaObject = (ArraySchemaObject | NonArraySchemaObject | MixedSchemaObject | boolean) & AnyOtherAttribute;
    export type ArraySchemaObject = {
        type?: ArraySchemaObjectType;
        items?: ReferenceObject | SchemaObject;
    } & BaseSchemaObject;
    export type NonArraySchemaObject = {
        type?: NonArraySchemaObjectType;
    } & BaseSchemaObject;
    type MixedSchemaObject = {
        type?: (ArraySchemaObjectType | NonArraySchemaObjectType)[];
        items?: ReferenceObject | SchemaObject;
    } & BaseSchemaObject;
    export type BaseSchemaObject = Modify<Omit<OpenAPIV3.BaseSchemaObject, 'nullable'>, {
        examples?: OpenAPIV3.BaseSchemaObject['example'][];
        exclusiveMinimum?: boolean | number;
        exclusiveMaximum?: boolean | number;
        contentMediaType?: string;
        $schema?: string;
        additionalProperties?: boolean | ReferenceObject | SchemaObject;
        properties?: {
            [name: string]: ReferenceObject | SchemaObject;
        };
        patternProperties?: {
            [name: string]: ReferenceObject | SchemaObject;
        };
        allOf?: (ReferenceObject | SchemaObject)[];
        oneOf?: (ReferenceObject | SchemaObject)[];
        anyOf?: (ReferenceObject | SchemaObject)[];
        not?: ReferenceObject | SchemaObject;
        discriminator?: DiscriminatorObject;
        externalDocs?: ExternalDocumentationObject;
        xml?: XMLObject;
        const?: any;
    }>;
    export type DiscriminatorObject = OpenAPIV3.DiscriminatorObject;
    export type XMLObject = OpenAPIV3.XMLObject;
    export type ReferenceObject = Modify<OpenAPIV3.ReferenceObject, {
        summary?: string;
        description?: string;
    }>;
    export type ExampleObject = OpenAPIV3.ExampleObject;
    export type MediaTypeObject = Modify<OpenAPIV3.MediaTypeObject, {
        schema?: SchemaObject | ReferenceObject;
        examples?: Record<string, ReferenceObject | ExampleObject>;
    }>;
    export type EncodingObject = OpenAPIV3.EncodingObject;
    export type RequestBodyObject = Modify<OpenAPIV3.RequestBodyObject, {
        content?: {
            [media: string]: MediaTypeObject;
        };
    }>;
    export type ResponsesObject = Record<string, ReferenceObject | ResponseObject>;
    export type ResponseObject = Modify<OpenAPIV3.ResponseObject, {
        headers?: {
            [header: string]: ReferenceObject | HeaderObject;
        };
        content?: {
            [media: string]: MediaTypeObject;
        };
        links?: {
            [link: string]: ReferenceObject | LinkObject;
        };
    }>;
    export type LinkObject = Modify<OpenAPIV3.LinkObject, {
        server?: ServerObject;
    }>;
    export type CallbackObject = Record<string, PathItemObject | ReferenceObject>;
    export type SecurityRequirementObject = OpenAPIV3.SecurityRequirementObject;
    export type ComponentsObject = Modify<OpenAPIV3.ComponentsObject, {
        schemas?: Record<string, SchemaObject>;
        responses?: Record<string, ReferenceObject | ResponseObject>;
        parameters?: Record<string, ReferenceObject | ParameterObject>;
        examples?: Record<string, ReferenceObject | ExampleObject>;
        requestBodies?: Record<string, ReferenceObject | RequestBodyObject>;
        headers?: Record<string, ReferenceObject | HeaderObject>;
        securitySchemes?: Record<string, ReferenceObject | SecuritySchemeObject>;
        links?: Record<string, ReferenceObject | LinkObject>;
        callbacks?: Record<string, ReferenceObject | CallbackObject>;
        pathItems?: Record<string, ReferenceObject | PathItemObject>;
    }>;
    export type SecuritySchemeObject = OpenAPIV3.SecuritySchemeObject;
    export type HttpSecurityScheme = OpenAPIV3.HttpSecurityScheme;
    export type ApiKeySecurityScheme = OpenAPIV3.ApiKeySecurityScheme;
    export type OAuth2SecurityScheme = OpenAPIV3.OAuth2SecurityScheme;
    export type OpenIdSecurityScheme = OpenAPIV3.OpenIdSecurityScheme;
    export type TagObject = OpenAPIV3.TagObject;
    export {};
}
export declare namespace OpenAPIV3 {
    type Document<T = {}> = {
        /**
         * Version of the OpenAPI specification
         * @see https://github.com/OAI/OpenAPI-Specification/tree/main/versions
         */
        openapi?: '3.0.0' | '3.0.1' | '3.0.2' | '3.0.3' | '3.0.4';
        swagger?: undefined;
        info?: InfoObject;
        servers?: ServerObject[];
        paths?: PathsObject<T>;
        components?: ComponentsObject;
        security?: SecurityRequirementObject[];
        tags?: TagObject[];
        externalDocs?: ExternalDocumentationObject;
    } & T & AnyOtherAttribute;
    type InfoObject = {
        title?: string;
        description?: string;
        termsOfService?: string;
        contact?: ContactObject;
        license?: LicenseObject;
        version?: string;
    };
    type ContactObject = {
        name?: string;
        url?: string;
        email?: string;
    };
    type LicenseObject = {
        name?: string;
        url?: string;
    };
    type ServerObject = {
        url?: string;
        description?: string;
        variables?: {
            [variable: string]: ServerVariableObject;
        };
    };
    type ServerVariableObject = {
        enum?: string[] | number[];
        default?: string | number;
        description?: string;
    };
    type PathsObject<T = {}, P extends {} = {}> = {
        [pattern: string]: (PathItemObject<T> & P) | undefined;
    };
    enum HttpMethods {
        GET = "get",
        PUT = "put",
        POST = "post",
        DELETE = "delete",
        OPTIONS = "options",
        HEAD = "head",
        PATCH = "patch",
        TRACE = "trace"
    }
    type PathItemObject<T = {}> = {
        $ref?: string;
        summary?: string;
        description?: string;
        servers?: ServerObject[];
        parameters?: (ReferenceObject | ParameterObject)[];
    } & {
        [method in HttpMethods]?: OperationObject<T>;
    } & T & AnyOtherAttribute;
    type OperationObject<T = {}> = {
        tags?: string[];
        summary?: string;
        description?: string;
        externalDocs?: ExternalDocumentationObject;
        operationId?: string;
        parameters?: (ReferenceObject | ParameterObject)[];
        requestBody?: ReferenceObject | RequestBodyObject;
        responses?: ResponsesObject;
        callbacks?: {
            [callback: string]: ReferenceObject | CallbackObject;
        };
        deprecated?: boolean;
        security?: SecurityRequirementObject[];
        servers?: ServerObject[];
    } & T & AnyOtherAttribute;
    type ExternalDocumentationObject = {
        description?: string;
        url?: string;
    };
    type ParameterObject = {
        name?: string;
        in?: string;
    } & ParameterBaseObject;
    type HeaderObject = {} & ParameterBaseObject;
    type ParameterBaseObject = {
        description?: string;
        required?: boolean;
        deprecated?: boolean;
        allowEmptyValue?: boolean;
        style?: string;
        explode?: boolean;
        allowReserved?: boolean;
        schema?: ReferenceObject | SchemaObject;
        example?: any;
        examples?: {
            [media: string]: ReferenceObject | ExampleObject;
        };
        content?: {
            [media: string]: MediaTypeObject;
        };
    };
    type NonArraySchemaObjectType = 'boolean' | 'object' | 'number' | 'string' | 'integer';
    type ArraySchemaObjectType = 'array';
    type SchemaObject = (ArraySchemaObject | NonArraySchemaObject) & AnyOtherAttribute;
    type ArraySchemaObject = {
        type?: ArraySchemaObjectType;
        items?: ReferenceObject | SchemaObject;
    } & BaseSchemaObject;
    type NonArraySchemaObject = {
        type?: NonArraySchemaObjectType;
    } & BaseSchemaObject;
    type BaseSchemaObject = {
        title?: string;
        description?: string;
        format?: string;
        default?: any;
        multipleOf?: number;
        maximum?: number;
        exclusiveMaximum?: boolean;
        minimum?: number;
        exclusiveMinimum?: boolean;
        maxLength?: number;
        minLength?: number;
        pattern?: string;
        additionalProperties?: boolean | ReferenceObject | SchemaObject;
        maxItems?: number;
        minItems?: number;
        uniqueItems?: boolean;
        maxProperties?: number;
        minProperties?: number;
        required?: string[];
        enum?: any[];
        properties?: {
            [name: string]: ReferenceObject | SchemaObject;
        };
        patternProperties?: {
            [name: string]: ReferenceObject | SchemaObject;
        };
        allOf?: (ReferenceObject | SchemaObject)[];
        oneOf?: (ReferenceObject | SchemaObject)[];
        anyOf?: (ReferenceObject | SchemaObject)[];
        not?: ReferenceObject | SchemaObject;
        nullable?: boolean;
        discriminator?: DiscriminatorObject;
        readOnly?: boolean;
        writeOnly?: boolean;
        xml?: XMLObject;
        externalDocs?: ExternalDocumentationObject;
        example?: any;
        deprecated?: boolean;
    };
    type DiscriminatorObject = {
        propertyName?: string;
        mapping?: {
            [value: string]: string;
        };
    };
    type XMLObject = {
        name?: string;
        namespace?: string;
        prefix?: string;
        attribute?: boolean;
        wrapped?: boolean;
    };
    type ReferenceObject = {
        $ref?: string;
    } & AnyOtherAttribute;
    type ExampleObject = {
        summary?: string;
        description?: string;
        value?: any;
        externalValue?: string;
    };
    type MediaTypeObject = {
        schema?: ReferenceObject | SchemaObject;
        example?: any;
        examples?: {
            [media: string]: ReferenceObject | ExampleObject;
        };
        encoding?: {
            [media: string]: EncodingObject;
        };
    };
    type EncodingObject = {
        contentType?: string;
        headers?: {
            [header: string]: ReferenceObject | HeaderObject;
        };
        style?: string;
        explode?: boolean;
        allowReserved?: boolean;
    };
    type RequestBodyObject = {
        description?: string;
        content?: {
            [media: string]: MediaTypeObject;
        };
        required?: boolean;
    };
    type ResponsesObject = {
        [code: string]: ReferenceObject | ResponseObject;
    };
    type ResponseObject = {
        description?: string;
        headers?: {
            [header: string]: ReferenceObject | HeaderObject;
        };
        content?: {
            [media: string]: MediaTypeObject;
        };
        links?: {
            [link: string]: ReferenceObject | LinkObject;
        };
    } & AnyOtherAttribute;
    type LinkObject = {
        operationRef?: string;
        operationId?: string;
        parameters?: {
            [parameter: string]: any;
        };
        requestBody?: any;
        description?: string;
        server?: ServerObject;
    };
    type CallbackObject = {
        [url: string]: PathItemObject;
    };
    type SecurityRequirementObject = {
        [name: string]: string[];
    };
    type ComponentsObject = {
        schemas?: {
            [key: string]: ReferenceObject | SchemaObject;
        };
        responses?: {
            [key: string]: ReferenceObject | ResponseObject;
        };
        parameters?: {
            [key: string]: ReferenceObject | ParameterObject;
        };
        examples?: {
            [key: string]: ReferenceObject | ExampleObject;
        };
        requestBodies?: {
            [key: string]: ReferenceObject | RequestBodyObject;
        };
        headers?: {
            [key: string]: ReferenceObject | HeaderObject;
        };
        securitySchemes?: {
            [key: string]: ReferenceObject | SecuritySchemeObject;
        };
        links?: {
            [key: string]: ReferenceObject | LinkObject;
        };
        callbacks?: {
            [key: string]: ReferenceObject | CallbackObject;
        };
    };
    type SecuritySchemeObject = HttpSecurityScheme | ApiKeySecurityScheme | OAuth2SecurityScheme | OpenIdSecurityScheme;
    type HttpSecurityScheme = {
        type?: 'http';
        description?: string;
        scheme?: string;
        bearerFormat?: string;
    };
    type ApiKeySecurityScheme = {
        type?: 'apiKey';
        description?: string;
        name?: string;
        in?: string;
    };
    type OAuth2SecurityScheme = {
        type?: 'oauth2';
        description?: string;
        flows?: {
            implicit?: {
                authorizationUrl?: string;
                refreshUrl?: string;
                scopes?: {
                    [scope: string]: string;
                };
            };
            password?: {
                tokenUrl?: string;
                refreshUrl?: string;
                scopes?: {
                    [scope: string]: string;
                };
            };
            clientCredentials?: {
                tokenUrl?: string;
                refreshUrl?: string;
                scopes?: {
                    [scope: string]: string;
                };
            };
            authorizationCode?: {
                authorizationUrl?: string;
                tokenUrl?: string;
                refreshUrl?: string;
                scopes?: {
                    [scope: string]: string;
                };
            };
        };
    };
    type OpenIdSecurityScheme = {
        type?: 'openIdConnect';
        description?: string;
        openIdConnectUrl?: string;
    };
    type TagObject = {
        name?: string;
        description?: string;
        externalDocs?: ExternalDocumentationObject;
    } & AnyOtherAttribute;
}
export declare namespace OpenAPIV2 {
    type Document<T = {}> = {
        /**
         * Version of the OpenAPI specification
         * @see https://github.com/OAI/OpenAPI-Specification/tree/main/versions
         */
        swagger?: '2.0';
        openapi?: never;
        basePath?: string;
        consumes?: MimeTypes;
        definitions?: DefinitionsObject;
        externalDocs?: ExternalDocumentationObject;
        host?: string;
        info?: InfoObject;
        parameters?: ParametersDefinitionsObject;
        paths?: PathsObject<T>;
        produces?: MimeTypes;
        responses?: ResponsesDefinitionsObject;
        schemes?: string[];
        security?: SecurityRequirementObject[];
        securityDefinitions?: SecurityDefinitionsObject;
        tags?: TagObject[];
    } & T & AnyOtherAttribute;
    type TagObject = {
        name?: string;
        description?: string;
        externalDocs?: ExternalDocumentationObject;
    } & AnyOtherAttribute;
    type SecuritySchemeObjectBase = {
        type?: 'basic' | 'apiKey' | 'oauth2';
        description?: string;
    };
    type SecuritySchemeBasic = {
        type?: 'basic';
    } & SecuritySchemeObjectBase;
    type SecuritySchemeApiKey = {
        type?: 'apiKey';
        name?: string;
        in?: string;
    } & SecuritySchemeObjectBase;
    type SecuritySchemeOauth2 = SecuritySchemeOauth2Implicit | SecuritySchemeOauth2AccessCode | SecuritySchemeOauth2Password | SecuritySchemeOauth2Application;
    type ScopesObject = {
        [index: string]: any;
    };
    type SecuritySchemeOauth2Base = {
        type?: 'oauth2';
        flow?: 'implicit' | 'password' | 'application' | 'accessCode';
        scopes?: ScopesObject;
    } & SecuritySchemeObjectBase;
    type SecuritySchemeOauth2Implicit = {
        flow?: 'implicit';
        authorizationUrl?: string;
    } & SecuritySchemeOauth2Base;
    type SecuritySchemeOauth2AccessCode = {
        flow?: 'accessCode';
        authorizationUrl?: string;
        tokenUrl?: string;
    } & SecuritySchemeOauth2Base;
    type SecuritySchemeOauth2Password = {
        flow?: 'password';
        tokenUrl?: string;
    } & SecuritySchemeOauth2Base;
    type SecuritySchemeOauth2Application = {
        flow?: 'application';
        tokenUrl?: string;
    } & SecuritySchemeOauth2Base;
    type SecuritySchemeObject = SecuritySchemeBasic | SecuritySchemeApiKey | SecuritySchemeOauth2;
    type SecurityDefinitionsObject = {
        [index: string]: SecuritySchemeObject;
    };
    type SecurityRequirementObject = {
        [index: string]: string[];
    };
    type ReferenceObject = {
        $ref: string;
    } & AnyOtherAttribute;
    type Response = ResponseObject | ReferenceObject;
    type ResponsesDefinitionsObject = {
        [index: string]: ResponseObject;
    };
    type Schema = SchemaObject | ReferenceObject;
    type ResponseObject = {
        description?: string;
        schema?: Schema;
        headers?: HeadersObject;
        examples?: ExampleObject;
    } & AnyOtherAttribute;
    type HeadersObject = {
        [index: string]: HeaderObject;
    };
    type HeaderObject = {
        description?: string;
    } & ItemsObject;
    type ExampleObject = {
        [index: string]: any;
    };
    type OperationObject<T = {}> = {
        tags?: string[];
        summary?: string;
        description?: string;
        externalDocs?: ExternalDocumentationObject;
        operationId?: string;
        consumes?: MimeTypes;
        produces?: MimeTypes;
        parameters?: Parameters;
        responses: ResponsesObject;
        schemes?: string[];
        deprecated?: boolean;
        security?: SecurityRequirementObject[];
    } & T & AnyOtherAttribute;
    type ResponsesObject = {
        [index: string]: Response | undefined;
        default?: Response;
    };
    type Parameters = (ReferenceObject | Parameter)[];
    type Parameter = InBodyParameterObject | GeneralParameterObject;
    type InBodyParameterObject = {
        schema?: Schema;
    } & ParameterObject;
    type GeneralParameterObject = {
        allowEmptyValue?: boolean;
    } & ParameterObject & ItemsObject;
    enum HttpMethods {
        GET = "get",
        PUT = "put",
        POST = "post",
        DELETE = "delete",
        OPTIONS = "options",
        HEAD = "head",
        PATCH = "patch"
    }
    type PathItemObject<T = {}> = {
        $ref?: string;
        parameters?: Parameters;
    } & {
        [method in HttpMethods]?: OperationObject<T>;
    };
    type PathsObject<T = {}> = {
        [index: string]: PathItemObject<T>;
    };
    type ParametersDefinitionsObject = {
        [index: string]: ParameterObject;
    };
    type ParameterObject = {
        name?: string;
        in?: string;
        description?: string;
        required?: boolean;
        [index: string]: any;
    };
    type MimeTypes = string[];
    type DefinitionsObject = {
        [index: string]: SchemaObject;
    };
    type SchemaObject = {
        [index: string]: any;
        discriminator?: string;
        readOnly?: boolean;
        xml?: XMLObject;
        externalDocs?: ExternalDocumentationObject;
        example?: any;
        default?: any;
        items?: ItemsObject | ReferenceObject;
        properties?: {
            [name: string]: SchemaObject;
        };
    } & IJsonSchema;
    type ExternalDocumentationObject = {
        [index: string]: any;
        description?: string;
        url?: string;
    };
    type ItemsObject = {
        type?: string;
        format?: string;
        items?: ItemsObject | ReferenceObject;
        collectionFormat?: string;
        default?: any;
        maximum?: number;
        exclusiveMaximum?: boolean;
        minimum?: number;
        exclusiveMinimum?: boolean;
        maxLength?: number;
        minLength?: number;
        pattern?: string;
        maxItems?: number;
        minItems?: number;
        uniqueItems?: boolean;
        enum?: any[];
        multipleOf?: number;
        $ref?: string;
    };
    type XMLObject = {
        [index: string]: any;
        name?: string;
        namespace?: string;
        prefix?: string;
        attribute?: boolean;
        wrapped?: boolean;
    };
    type InfoObject = {
        title?: string;
        description?: string;
        termsOfService?: string;
        contact?: ContactObject;
        license?: LicenseObject;
        version?: string;
    };
    type ContactObject = {
        name?: string;
        url?: string;
        email?: string;
    };
    type LicenseObject = {
        name?: string;
        url?: string;
    };
}
export type IJsonSchema = {
    id?: string;
    $schema?: string;
    title?: string;
    description?: string;
    multipleOf?: number;
    maximum?: number;
    exclusiveMaximum?: boolean;
    minimum?: number;
    exclusiveMinimum?: boolean;
    maxLength?: number;
    minLength?: number;
    pattern?: string;
    additionalItems?: boolean | IJsonSchema;
    items?: IJsonSchema | IJsonSchema[];
    maxItems?: number;
    minItems?: number;
    uniqueItems?: boolean;
    maxProperties?: number;
    minProperties?: number;
    required?: string[];
    additionalProperties?: boolean | IJsonSchema;
    definitions?: {
        [name: string]: IJsonSchema;
    };
    properties?: {
        [name: string]: IJsonSchema;
    };
    patternProperties?: {
        [name: string]: IJsonSchema;
    };
    dependencies?: {
        [name: string]: IJsonSchema | string[];
    };
    enum?: any[];
    type?: string | string[];
    allOf?: IJsonSchema[];
    anyOf?: IJsonSchema[];
    oneOf?: IJsonSchema[];
    not?: IJsonSchema;
    $ref?: string;
} & AnyOtherAttribute;
export {};
//# sourceMappingURL=openapi-types.d.ts.map