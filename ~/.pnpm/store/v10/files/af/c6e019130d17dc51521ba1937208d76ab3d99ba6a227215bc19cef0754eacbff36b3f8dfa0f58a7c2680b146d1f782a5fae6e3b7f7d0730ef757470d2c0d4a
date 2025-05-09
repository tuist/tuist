import { httpie } from '../../../httpsnippet-lite/esm/targets/shell/httpie/client.js';
import { convertWithHttpSnippetLite } from '../../../utils/convertWithHttpSnippetLite.js';

/**
 * shell/httpie
 */
const shellHttpie = {
    target: 'shell',
    client: 'httpie',
    title: 'HTTPie',
    generate(request) {
        // TODO: Write an own converter
        return convertWithHttpSnippetLite(httpie, request);
    },
};

export { shellHttpie };
