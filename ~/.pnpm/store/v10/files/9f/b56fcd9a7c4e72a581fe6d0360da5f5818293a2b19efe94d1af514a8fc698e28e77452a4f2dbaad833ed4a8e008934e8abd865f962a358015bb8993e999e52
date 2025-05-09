export type Option = {
    id: string;
    label: string;
    isDeletable?: boolean;
    [x: string]: any;
};
export type OptionGroup = {
    label: string;
    options: Option[];
};
/** Type guard to check if an option is a group */
export declare function isGroup(option: Option | OptionGroup): option is OptionGroup;
/** Type guard to check if an array of options is an array of groups */
export declare function isGroups(options: Option[] | OptionGroup[]): options is OptionGroup[];
/** Available slots for the combobox */
export type ComboboxSlots = {
    /** The reference element / trigger for the combobox */
    default(): any;
    /** A slot for contents before the combobox options */
    before?(): any;
    /** A slot for contents after the combobox options */
    after?(): any;
};
//# sourceMappingURL=types.d.ts.map