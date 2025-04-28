import { parseIriReference, resolveIri } from "@hyperjump/uri";


const uriSchemePlugins = {};

export const addUriSchemePlugin = (scheme, plugin) => {
  uriSchemePlugins[scheme] = plugin;
};

export const removeUriSchemePlugin = (scheme) => {
  delete uriSchemePlugins[scheme];
};

export const retrieve = (uri, baseUri) => {
  uri = resolveIri(uri, baseUri);
  const { scheme } = parseIriReference(uri);

  if (!(scheme in uriSchemePlugins)) {
    throw new UnsupportedUriSchemeError(scheme, `The '${scheme}:' URI scheme is not supported. Use the 'addUriSchemePlugin' function to add support for '${scheme}:' URIs.`);
  }

  return uriSchemePlugins[scheme].retrieve(uri, baseUri);
};

export class UnsupportedUriSchemeError extends Error {
  constructor(scheme, message = undefined) {
    super(message);
    this.name = this.constructor.name;
    this.scheme = scheme;
  }
}
