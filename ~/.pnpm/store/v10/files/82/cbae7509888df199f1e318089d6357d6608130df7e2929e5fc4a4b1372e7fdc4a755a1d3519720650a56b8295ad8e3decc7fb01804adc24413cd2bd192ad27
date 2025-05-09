import { type SecuritySchemeGroup, type SecuritySchemeOption } from '../../../views/Request/consts';
import type { Collection, Operation, SecurityScheme } from '@scalar/oas-utils/entities/spec';
type DisplayScheme = {
    type: SecurityScheme['type'] | 'complex';
    nameKey: SecurityScheme['nameKey'];
    uid: SecurityScheme['uid'];
};
/** Format a scheme object into a display object */
export declare const formatScheme: (s: DisplayScheme) => {
    id: string & import("zod").BRAND<"securityScheme">;
    label: string;
};
/** Formats complex security schemes */
export declare const formatComplexScheme: (uids: string[], securitySchemes: Record<string, DisplayScheme>) => {
    id: string & import("zod").BRAND<"securityScheme">;
    label: string;
};
/** Compute what the security requirements should be for a request */
export declare const getSecurityRequirements: (operation?: Operation, collection?: Collection) => Record<string, string[]>[];
/**
 * Generates the options for the security scheme combobox
 *
 * contains either a flat list, or different groups of required, available, and add new
 */
export declare const getSchemeOptions: (filteredRequirements: Collection["security"], collectionSchemeUids: Collection["securitySchemes"], securitySchemes: Record<string, DisplayScheme>, isReadOnly?: boolean) => SecuritySchemeOption[] | SecuritySchemeGroup[];
export {};
//# sourceMappingURL=auth.d.ts.map