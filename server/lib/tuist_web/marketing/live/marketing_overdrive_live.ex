defmodule TuistWeb.Marketing.MarketingOverdriveLive do
  @moduledoc """
  The Overdrive directory: popular open source projects Tuist forked and
  wired up to Tuist, each with its headline numbers and a link to its public
  dashboard. Entries are curated in `Tuist.Marketing.Overdrive`.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.MarketingOverdriveComponents

  alias Tuist.Marketing.Overdrive
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Marketing.SocialCards

  on_mount({TuistWeb.Authentication, :mount_current_user})

  embed_templates "marketing_overdrive_live/*"

  def render(assigns), do: overdrive(assigns)

  def mount(_params, _session, socket) do
    title = dgettext("marketing", "Overdrive")

    socket =
      socket
      |> assign(:projects, Overdrive.list_projects())
      |> assign(:period_days, Overdrive.period_days())
      |> assign(:head_title, title)
      |> assign(
        :head_description,
        dgettext(
          "marketing",
          "Popular open source projects, forked and put in Overdrive with Tuist. See how much faster they'd build and test."
        )
      )
      |> assign(
        :head_image,
        SocialCards.head_image("overdrive", fn -> OpenGraph.image_path(:marketing, title: title) end)
      )
      |> assign(:head_twitter_card, "summary_large_image")

    {:ok, socket}
  end

  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
    {:noreply, assign(socket, :current_path, current_path)}
  end
end
