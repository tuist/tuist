declare const supportedLocales: readonly ["ach", "af", "am", "an", "ar", "ast", "az", "be", "bg", "bn", "br", "bs", "ca", "cak", "ckb", "cs", "cy", "da", "de", "dsb", "el", "en", "eo", "es", "et", "eu", "fa", "ff", "fi", "fr", "fy", "ga", "gd", "gl", "he", "hr", "hsb", "hu", "ia", "id", "it", "ja", "ka", "kk", "kn", "ko", "lb", "lo", "lt", "lv", "meh", "ml", "ms", "nl", "nn", "no", "oc", "pl", "pt", "rm", "ro", "ru", "sc", "scn", "sk", "sl", "sr", "sv", "szl", "tg", "th", "tr", "uk", "zh-CN", "zh-TW"];
declare const placeholderFields: readonly ["year", "month", "day"];
type PlaceholderField = (typeof placeholderFields)[number];
export type SupportedLocale = (typeof supportedLocales)[number];
export type PlaceholderMap = Record<SupportedLocale, Record<PlaceholderField, string>>;
type Field = 'era' | 'year' | 'month' | 'day' | 'hour' | 'minute' | 'second' | 'dayPeriod';
export declare function getPlaceholder(field: Field, value: string, locale: SupportedLocale | (string & {})): string;
export {};
