import { native } from '../../../httpsnippet-lite/esm/targets/ruby/native/client.js';
import { convertWithHttpSnippetLite } from '../../../utils/convertWithHttpSnippetLite.js';

/**
 * ruby/native
 */
const rubyNative = {
    target: 'ruby',
    client: 'native',
    title: 'net::http',
    generate(request) {
        // TODO: Write an own converter
        return convertWithHttpSnippetLite(native, request);
    },
};

export { rubyNative };
