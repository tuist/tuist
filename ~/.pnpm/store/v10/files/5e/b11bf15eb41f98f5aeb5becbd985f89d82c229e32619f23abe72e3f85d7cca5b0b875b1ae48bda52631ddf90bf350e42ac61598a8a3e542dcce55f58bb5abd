import { acceptableMediaTypes } from "../media-types/media-types.js";


const successStatus = new Set([200, 203]);

const retrieve = async (uri) => {
  const response = await fetch(uri, { headers: { Accept: acceptableMediaTypes() } });

  if (response.status >= 400) {
    throw new HttpError(response, `Failed to retrieve '${uri}'`);
  }

  if (!successStatus.has(response.status)) {
    throw new HttpError(response, "Unsupported HTTP response status code");
  }

  return response;
};

export const httpSchemePlugin = { retrieve };

class HttpError extends Error {
  constructor(response, message = undefined) {
    super(`${response.status} ${response.statusText}${message ? ` -- ${message}` : ""}`);
    this.name = this.constructor.name;
    this.response = response;
  }
}
