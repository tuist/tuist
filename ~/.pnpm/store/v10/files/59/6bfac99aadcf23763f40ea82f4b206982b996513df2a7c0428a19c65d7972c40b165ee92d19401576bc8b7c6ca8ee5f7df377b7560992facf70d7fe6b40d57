import { addMediaTypePlugin } from "./media-types/media-types.js";
import { jrefMediaTypePlugin } from "./media-types/jref-media-type-plugin.js";
import { addUriSchemePlugin } from "./uri-schemes/uri-schemes.js";
import { httpSchemePlugin } from "./uri-schemes/http-scheme-plugin.js";
import { fileSchemePlugin } from "./uri-schemes/file-scheme-plugin.js";


addMediaTypePlugin("application/reference+json", jrefMediaTypePlugin);

addUriSchemePlugin("http", httpSchemePlugin);
addUriSchemePlugin("https", httpSchemePlugin);
addUriSchemePlugin("file", fileSchemePlugin);

export {
  get,
  value,
  typeOf,
  has,
  length,
  step,
  iter,
  keys,
  values,
  entries,
  RetrievalError
} from "./browser/browser.js";

export {
  addMediaTypePlugin,
  removeMediaTypePlugin,
  setMediaTypeQuality,
  acceptableMediaTypes,
  UnsupportedMediaTypeError,
  UnknownMediaTypeError
} from "./media-types/media-types.js";

export {
  addUriSchemePlugin,
  removeUriSchemePlugin,
  retrieve,
  UnsupportedUriSchemeError
} from "./uri-schemes/uri-schemes.js";
