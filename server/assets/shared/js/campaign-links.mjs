// Carries a visit's campaign parameters (utm_*, ref) along links within the
// site, so a sign-up a few pages after landing still knows where the visit
// came from. Only the URL is used: nothing is stored on the visitor's device.
// The server counts the landing and stores the campaign at sign-up; see
// TuistWeb.Plugs.AttributionPlug.

const CAMPAIGN_PARAMS = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "ref"];

/**
 * The URL to navigate to instead of `href` from `pageUrl`, or null to leave
 * the link alone: links to other sites, links that name a campaign of their
 * own, and jumps within the same page.
 */
export function carryCampaign(href, pageUrl) {
  const page = new URL(pageUrl);
  const campaign = CAMPAIGN_PARAMS.filter((name) => page.searchParams.has(name));
  if (campaign.length === 0) return null;

  let target;
  try {
    target = new URL(href, page);
  } catch {
    return null;
  }

  if (target.origin !== page.origin) return null;
  if (CAMPAIGN_PARAMS.some((name) => target.searchParams.has(name))) return null;
  if (target.pathname === page.pathname && target.search === "" && target.hash !== "") return null;

  for (const name of campaign) target.searchParams.set(name, page.searchParams.get(name));
  return target.toString();
}

export function initCampaignLinks(doc = document) {
  if (!CAMPAIGN_PARAMS.some((name) => new URL(doc.location.href).searchParams.has(name))) return;

  // Rewrite the link just before the browser follows it. `pointerdown` also
  // covers middle clicks and the context menu's "open in new tab".
  const rewrite = (event) => {
    const link = event.target instanceof Element ? event.target.closest("a[href]") : null;
    if (!link) return;
    const carried = carryCampaign(link.getAttribute("href"), doc.location.href);
    if (carried) link.setAttribute("href", carried);
  };

  doc.addEventListener("pointerdown", rewrite, true);
  doc.addEventListener("click", rewrite, true);
}
