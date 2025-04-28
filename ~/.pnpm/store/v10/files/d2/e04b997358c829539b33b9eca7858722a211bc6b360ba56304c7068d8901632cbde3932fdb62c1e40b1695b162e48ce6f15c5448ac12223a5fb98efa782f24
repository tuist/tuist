import fs from 'node:fs';
import { ERRORS } from '../../configuration/index.js';
import { dirname, join } from '../../polyfills/path.js';
import { isJson } from '../../utils/isJson.js';
import { isYaml } from '../../utils/isYaml.js';

const readFiles = () => {
    return {
        check(value) {
            // Not a string
            if (typeof value !== 'string') {
                return false;
            }
            // URL
            if (value.startsWith('http://') || value.startsWith('https://')) {
                return false;
            }
            // Line breaks
            if (value.includes('\n')) {
                return false;
            }
            // JSON
            if (isJson(value)) {
                return false;
            }
            // YAML (run through YAML.parse)
            if (isYaml(value)) {
                return false;
            }
            return true;
        },
        async get(value) {
            if (!fs.existsSync(value)) {
                throw new Error(ERRORS.FILE_DOES_NOT_EXIST.replace('%s', value));
            }
            try {
                return fs.readFileSync(value, 'utf-8');
            }
            catch (error) {
                console.error('[readFiles]', error);
                return false;
            }
        },
        resolvePath(value, reference) {
            const dir = dirname(value);
            return join(dir, reference);
        },
        getDir(value) {
            return dirname(value);
        },
        getFilename(value) {
            return value.split('/').pop();
        },
    };
};

export { readFiles };
