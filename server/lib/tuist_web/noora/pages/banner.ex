defmodule TuistWeb.Noora.Pages.Banner do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Banner",
    description:
      "Announces a message that concerns the whole page, account, or product, across the full width of its container.",
    components: [{Noora.Banner, :banner}],
    guidelines: [
      "Use a banner for messages about the whole page or account, such as billing problems or maintenance. For messages about a specific piece of content, use an alert next to it.",
      "Keep the title and description short. They sit side by side on one row, separated by a dot.",
      "Match the status to the message: `success` confirms, `warning` asks for attention, `error` reports a problem that needs action, `information` gives context.",
      "Only `primary` accepts a custom `icon`. The other statuses always show their own icon.",
      "Add at most one link with the `action` slot, for the next step such as Learn more or Update payment method. Use a large `link_button`; it takes the banner's text color.",
      "Dismissing hides the banner in the browser with `JS.hide`. It comes back on the next page load unless you stop rendering it."
    ]

  example "Primary",
    description:
      "The default status, for announcements. It has an animated dither wave in the background and can show an icon of your choice.",
    layout: :column do
    ~H"""
    <.banner
      id="banner-primary"
      status="primary"
      title="Introducing Tuist Runners"
      description="Run your CI jobs on Tuist-hosted macOS machines"
    >
      <:icon><.server /></:icon>
    </.banner>
    """
  end

  example "Statuses", description: "Each status sets the color and a fixed icon.", layout: :column do
    ~H"""
    <.banner
      id="banner-status-information"
      status="information"
      title="You are viewing a public project"
      description="Sign in to see your organization's projects"
    />
    <.banner
      id="banner-status-success"
      status="success"
      title="Your organization is on the Pro plan"
      description="Remote cache and previews are now unlimited"
    />
    <.banner
      id="banner-status-warning"
      status="warning"
      title="Scheduled maintenance on October 24"
      description="Previews may be unavailable for up to 10 minutes"
    />
    <.banner
      id="banner-status-error"
      status="error"
      title="We could not charge your card"
      description="Update your payment method to keep using the remote cache"
    />
    """
  end

  example "With a link",
    description: "The `action` slot adds a link after the description. Arrows come from the link button's icon slots.",
    layout: :column do
    ~H"""
    <.banner
      id="banner-action-success"
      status="success"
      title="You're on the Pro plan"
      description="Unlimited cache and previews"
    >
      <:action>
        <.link_button label="See plan" size="large" href="#">
          <:icon_right><.chevron_right /></:icon_right>
        </.link_button>
      </:action>
    </.banner>
    <.banner
      id="banner-action-error"
      status="error"
      title="Your payment failed"
    >
      <:action>
        <.link_button label="Update card" size="large" href="#" />
      </:action>
    </.banner>
    """
  end

  example "Title only", description: "Leave out the description when the title says it all.", layout: :column do
    ~H"""
    <.banner id="banner-title-only" status="success" title="Your email address was confirmed" />
    """
  end

  example "Dismissible", description: "Shows a dismiss button that hides the banner.", layout: :column do
    ~H"""
    <.banner
      id="banner-dismissible"
      status="information"
      title="Bundle size insights are available"
      description="Upload a bundle to compare it against main"
      dismissible
    />
    """
  end
end
