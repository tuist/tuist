import { localizedString } from "./i18n.mjs";
export function comingSoonBadge(locale) {
  return `<span style="background: var(--vp-custom-block-tip-code-bg); color: var(--vp-c-tip-1); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">${localizedString(
    locale,
    "badges.coming-soon"
  )}</span>`;
}

export function xcodeProjCompatibleBadge(locale) {
  return `<span style="background: var(--vp-badge-warning-bg); color: var(--vp-badge-warning-text); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">${localizedString(
    locale,
    "badges.xcodeproj-compatible"
  )}</span>`;
}
