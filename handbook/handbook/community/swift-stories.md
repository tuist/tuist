---
{
  "title": "Swift Stories Newsletter",
  "titleTemplate": ":title | Community | Tuist Handbook",
  "description": "Swift Stories is a bi-weeky newsletter that features stories from and for the Swift community to spark inspiration."
}
---
# Swift Stories Newsletter

[Swift Stories](https://community.tuist.dev/t/swift-stories-newsletter/275) is a bi-weeky newsletter that features stories from and for the Swift community to spark inspiration.

> [!NOTE]
> The newsletter issues are curated by Tuist, but **not about Tuist**. While readers of the newsletter might build bonds with the Tuist brand and community through the newsletter, the primary goal is to provide value to the Swift community.

## Overview

The list of subscribers is managed by our self-hosted instance of [Listmonk](https://listmonk.app) at [lists.tuist.dev](https://lists.tuist.dev). People can subscribe through the form at [tuist.dev/newsletter](https://tuist.dev/newsletter), and they can unsubscribe at any time by clicking the link at the bottom of the newsletter.

Issues are also available through the web (e.g. [tuist.dev/newsletter/issues/1](https://tuist.dev/newsletter/issues/1)), and the [Atom](https://tuist.dev/newsletter/atom.xml) and [RSS](https://tuist.dev/newsletter/rss.xml) feeds.

## Write a new issue

1. Create a new file at `/priv/marketing/newsletter/issues/{number}.yml` where `number` is the number of the issue. We recommend updating the last one and updating the content.
2. You can dev the server, and acccess the issue at `/newsletter/issues/{number}`.
3. Once you are happy with the content, send yourself a test email to ensure the content looks good. For that, access the same page with the param `?email`, and using the developer tools, copy the whole markup of the page.
4. At [lists.tuist.dev](https://lists.tuist.dev), create a new campaign. The name and subject are not relevant because it's just a test. **Ensure you select the testing list and the Swift Stories template**. In the Content tab, paste the raw HTML, and then send the campaign. The team should receive an email with the content.

## Publish a new issue

Once the issue is ready, you can schedule it for publication. To do that, you need to:

1. Create a new campaign. This time it'll represent the actual issue, so make sure the information is accurate.
2. In `name` and `subject` copy the value of the `<title/>` attribute in the HTML.
3. **Select the Swift Stories** list, and the date when it'll get delivered.
4. In the Content tab, paste the raw HTML.
5. Send the campaign.
