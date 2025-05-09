import { parse } from 'yaml';

function isYaml(value) {
    // Line breaks
    if (!value.includes('\n')) {
        return false;
    }
    try {
        parse(value, {
            maxAliasCount: 10000,
        });
        return true;
    }
    catch (error) {
        return false;
    }
}

export { isYaml };
