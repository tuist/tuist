// Get the browser language preferences for LiveView locale negotiation.
export function getUserLocale() {
  return navigator.languages?.join(",") || navigator.language || "en";
}
