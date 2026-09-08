defmodule TuistWeb.LayoutComponents do
  @moduledoc ~S"""
  A collection of components for layouts.
  """
  use TuistWeb, :live_component

  import TuistWeb.CSP, only: [get_csp_nonce: 0]

  def head_favicon_links(assigns) do
    ~H"""
    <link rel="icon" href="/favicon.ico" sizes="any" />
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />
    """
  end

  def head_support_chat_script(assigns) do
    ~H"""
    <script
      :if={!Map.get(assigns, :support_chat_disabled?, false)}
      defer
      nonce={get_csp_nonce()}
      src={
        URI.parse("https://atlas.tuist.dev")
        |> URI.append_path("/support/chat.js")
        |> URI.to_string()
      }
    >
    </script>
    """
  end

  defp default_description do
    dgettext(
      "dashboard",
      "Tuist is build infrastructure for productive teams, integrating into the build toolchains they already use."
    )
  end

  def head_meta_meta_tags(assigns) do
    ~H"""
    <meta name="description" content={assigns[:head_description] || default_description()} />
    <%= if not is_nil(assigns[:head_keywords]) do %>
      <meta name="keywords" content={assigns[:head_keywords] |> Enum.join(", ")} />
    <% end %>
    <meta property="og:url" content={Tuist.Environment.app_url(path: assigns[:current_path] || "/")} />
    <meta property="og:type" content={assigns[:head_og_type] || "website"} />
    <meta property="og:title" content={assigns[:head_title] || "Tuist"} />
    <meta property="og:description" content={assigns[:head_description] || default_description()} />
    <meta
      :if={not is_nil(assigns[:head_site_name])}
      property="og:site_name"
      content={assigns[:head_site_name]}
    />
    <meta
      :if={not is_nil(assigns[:head_published_time])}
      property="article:published_time"
      content={assigns[:head_published_time]}
    />
    <meta
      :if={not is_nil(assigns[:head_modified_time])}
      property="article:modified_time"
      content={assigns[:head_modified_time]}
    />
    <meta
      :if={not is_nil(assigns[:head_article_author])}
      property="article:author"
      content={assigns[:head_article_author]}
    />
    <meta
      :if={not is_nil(assigns[:head_fediverse_creator])}
      name="fediverse:creator"
      content={assigns[:head_fediverse_creator]}
    />

    <%= if is_nil(assigns[:head_image]) do %>
      <meta
        property="og:image"
        content={Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")}
      />
    <% else %>
      <meta property="og:image" content={assigns[:head_image]} />
    <% end %>
    <%= case Map.get(assigns, :head_image_dimensions, {1920, 1080}) do %>
      <% {width, height} -> %>
        <meta property="og:image:width" content={width} />
        <meta property="og:image:height" content={height} />
      <% nil -> %>
    <% end %>
    """
  end

  def head_x_meta_tags(assigns) do
    ~H"""
    <%= if is_nil(assigns[:head_twitter_card]) do %>
      <meta name="twitter:card" content="summary" />
    <% else %>
      <meta name="twitter:card" content={assigns[:head_twitter_card]} />
    <% end %>
    <meta name="twitter:site" content="@tuistdev" />
    <%= if is_nil(assigns[:head_image]) do %>
      <meta
        name="twitter:image"
        content={Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")}
      />
    <% else %>
      <meta name="twitter:image" content={assigns[:head_image]} />
    <% end %>
    <meta name="twitter:title" content={assigns[:head_title] || "Tuist"} />
    <meta name="twitter:description" content={assigns[:head_description] || default_description()} />
    <meta
      property="twitter:domain"
      content={Tuist.Environment.app_url(path: "/") |> URI.parse() |> Map.get(:host)}
    />
    <meta
      property="twitter:url"
      content={Tuist.Environment.app_url(path: assigns[:current_path] || "/")}
    />
    """
  end

  attr(:page_section, :string, default: nil)

  def head_analytics_scripts(assigns) do
    analytics_enabled =
      Tuist.Environment.analytics_enabled?() and not Map.get(assigns, :analytics_disabled?, false)

    analytics_opts = %{
      enabled: analytics_enabled,
      collector_url: Tuist.Environment.faro_collector_url(),
      app_name: "tuist-web",
      app_version: Tuist.Environment.version(),
      environment: to_string(Tuist.Environment.env()),
      page_section: assigns.page_section
    }

    assigns = assign(assigns, :analytics_opts, analytics_opts)

    ~H"""
    <script nonce={get_csp_nonce()}>
      globalThis.analytics = <%= raw JSON.encode!(@analytics_opts) %>;
    </script>
    """
  end
end
