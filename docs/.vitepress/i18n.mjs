import enStrings from "./strings/en.json";
import ruStrings from "./strings/ru.json";
import koStrings from "./strings/ko.json";
import jaStrings from "./strings/ja.json";
import esStrings from "./strings/es.json";
import ptStrings from "./strings/pt.json";

const strings = {
  en: enStrings,
  ru: ruStrings,
  ko: koStrings,
  ja: jaStrings,
  es: esStrings,
  pt: ptStrings,
};

export function localizedString(locale, key) {
  const getString = (localeStrings, key) => {
    const keys = key.split(".");
    let current = localeStrings;

    for (const k of keys) {
      if (current && current.hasOwnProperty(k)) {
        current = current[k];
      } else {
        return undefined;
      }
    }
    return current;
  };

  let localizedValue = getString(strings[locale], key);

  if (localizedValue === undefined && locale !== "en") {
    localizedValue = getString(strings["en"], key);
  }

  return localizedValue;
}
