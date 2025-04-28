import { parse } from "../jref/index.js";


export const jrefMediaTypePlugin = {
  parse: async (response) => {
    return {
      baseUri: response.url,
      root: parse(await response.text()),
      anchorLocation: anchorLocation
    };
  },
  fileMatcher: (path) => /[^/]\.jref$/.test(path)
};

const anchorLocation = (fragment) => decodeURI(fragment || "");
