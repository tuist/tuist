---
{
  "title": "Tuist Digest Newsletter",
  "titleTemplate": ":title | Community | Tuist Handbook",
  "description": "Tuist Digest is a newsletter showcasing the most important work happening in Tuist and our vision for the future of app development at scale."
}
---
# Tuist Digest Newsletter

[Tuist Digest](https://community.tuist.dev/t/swift-stories-newsletter/275) is a newsletter about surfacing the signal from all the work that's happening in Tuist. A newsletter showcasing the most important work happening in Tuist and our vision for the future of app development at scale. Each edition highlights recent developments, upcoming features, and insights into how we're shaping the tools and practices teams need to build better apps, faster.

## Overview

The list of subscribers, templates, and campaigns are all managed using [Loops](https://app.loops.so/). People can subscribe through the form at [tuist.dev/newsletter](https://tuist.dev/newsletter), and they can unsubscribe at any time by clicking the link at the bottom of the newsletter.

Issues are also available through the web (e.g. [tuist.dev/newsletter/issues/1](https://tuist.dev/newsletter/issues/1)), and the [Atom](https://tuist.dev/newsletter/atom.xml) and [RSS](https://tuist.dev/newsletter/rss.xml) feeds.

## Write a new issue

1. Create a new file at `/priv/marketing/newsletter/issues/{number}.yml` where `number` is the number of the issue. We recommend updating the last one and updating the content.
2. You can dev the server, and acccess the issue at `/newsletter/issues/{number}`.
3. Once you are happy with the content, send yourself a test email to ensure the content looks good. For that, access the same page with the param `?email`, and using the developer tools, copy the whole markup of the page.
4. At [LoopsLoops](https://appapp.loopsloops.so/so/), create a new campaign. The name and subject are not relevant because it's just a test. **Ensure you select the testing list and the TuistTuist DigestDigest template**. In the Content tab, paste the raw HTML, and then send the campaign. The team should receive an email with the content.

## Publish a new issue

Once the issue is ready, you can schedule it for publication. To do that, you need to:

1. Create a new campaign at [Loops](https://app.loops.so/). This time it'll represent the actual issue, so make sure the information is accurate.
2. In `name` and `subject` copy the value of the `<title/>` attribute in the HTML.
3. **Select the TuistTuist DigestDigest** list, and the date when it'll get delivered.
4. In the Content tab, paste the raw HTML.
5. Send the campaign.