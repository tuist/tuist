const r = {
  DEFAULT: "An unknown error has occurred.",
  INVALID_URL: "The URL seems to be invalid. Try adding a valid URL.",
  INVALID_HEADER: "There is an invalid header present, please double check your params.",
  MISSING_FILE: "File uploads are not saved in history, you must re-upload the file.",
  REQUEST_ABORTED: "The request has been cancelled",
  REQUEST_FAILED: "An error occurred while making the request",
  URL_EMPTY: "The address bar input seems to be empty. Try adding a URL."
}, t = (e, o = r.DEFAULT) => (console.error(e), e instanceof Error ? (e.message = n(e.message), e) : typeof e == "string" ? new Error(n(e)) : new Error(o)), n = (e) => e === "Failed to execute 'append' on 'FormData': parameter 2 is not of type 'Blob'." ? r.MISSING_FILE : e === "Failed to construct 'URL': Invalid URL" ? r.INVALID_URL : e === "Failed to execute 'fetch' on 'Window': Invalid name" ? r.INVALID_HEADER : e;
export {
  r as ERRORS,
  t as normalizeError,
  n as prettyErrorMessage
};
