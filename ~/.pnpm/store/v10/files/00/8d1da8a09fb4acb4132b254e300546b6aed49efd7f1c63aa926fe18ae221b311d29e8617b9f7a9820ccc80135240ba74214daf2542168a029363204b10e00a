import Ajv04 from 'ajv-draft-04';
import Ajv2020 from 'ajv/dist/2020.js';
import { type OpenApiVersion } from '../../configuration/index.ts';
import type { AnyObject, Filesystem, ThrowOnErrorOption, ValidateResult } from '../../types/index.ts';
/**
 * Configure available JSON Schema versions
 */
export declare const jsonSchemaVersions: {
    'http://json-schema.org/draft-04/schema#': typeof Ajv04;
    'https://json-schema.org/draft/2020-12/schema': typeof Ajv2020;
};
export declare class Validator {
    version: '2.0' | '3.0' | '3.1';
    static supportedVersions: ("2.0" | "3.0" | "3.1")[];
    protected ajvValidators: Record<string, ((specification: AnyObject) => boolean) & {
        errors: string;
    }>;
    protected errors: string;
    protected specificationVersion: string;
    protected specificationType: string;
    specification: AnyObject;
    /**
     * Checks whether a specification is valid and all references can be resolved.
     */
    validate(filesystem: Filesystem, options?: ThrowOnErrorOption): Promise<ValidateResult>;
    /**
     * Ajv JSON schema validator
     */
    getAjvValidator(version: OpenApiVersion): Promise<any>;
}
//# sourceMappingURL=Validator.d.ts.map