import { wget } from '../../../httpsnippet-lite/esm/targets/shell/wget/client.js';
import { convertWithHttpSnippetLite } from '../../../utils/convertWithHttpSnippetLite.js';

/**
 * shell/wget
 */
const shellWget = {
    target: 'shell',
    client: 'wget',
    title: 'Wget',
    generate(request) {
        // TODO: Write an own converter
        return convertWithHttpSnippetLite(wget, request);
    },
};

export { shellWget };
