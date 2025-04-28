let emitDeprecation = false;
function enableDeprecationWarnings(value = true) {
  emitDeprecation = value;
}
function warnDeprecated(message) {
  if (emitDeprecation)
    console.trace(`[SHIKI DEPRECATE]: ${message}`);
}

export { enableDeprecationWarnings as e, warnDeprecated as w };
