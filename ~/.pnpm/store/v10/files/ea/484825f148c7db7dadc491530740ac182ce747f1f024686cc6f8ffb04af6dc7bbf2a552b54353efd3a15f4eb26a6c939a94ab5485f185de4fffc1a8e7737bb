import { g as MetaFlat } from './shared/zhead.177ad851.mjs';

interface MetaSchema {
    name: string;
    key: 'charset' | 'name' | 'property' | 'http-equiv';
    type?: 'standard' | 'facebook' | 'twitter' | 'google' | 'robots' | 'other' | 'open-graph-protocol';
    description: string;
    color?: string;
    examples: {
        value: string;
        description: string;
    }[];
    tips?: {
        title: string;
        description: string;
    }[];
    tags?: string | string[];
    documentation?: string[];
    parameters?: {
        value: string;
        description: string;
    }[];
}

declare const metaFlatSchema: Record<keyof MetaFlat, MetaSchema>;

export { MetaFlat, type MetaSchema, metaFlatSchema };
