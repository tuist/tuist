defmodule TuistWeb.Marketing.MarketingOverdriveProjectLive do
  @moduledoc """
  An Overdrive project page: a Tuist fork's headline numbers, links to its
  public dashboard, the fork and the upstream project, and the shareable
  card its links unfurl to.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.MarketingOverdriveComponents

  alias Tuist.Marketing.Overdrive
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph

  on_mount({TuistWeb.Authentication, :mount_current_user})

  embed_templates "marketing_overdrive_project_live/*"

  def render(assigns), do: overdrive_project(assigns)

  def mount(%{"account_handle" => account_handle, "project_handle" => project_handle}, _session, socket) do
    case Overdrive.get_project(account_handle, project_handle) do
      {:ok, project} ->
        image_url =
          Tuist.Environment.app_url(
            path: OpenGraph.image_path(:marketing_overdrive, Overdrive.og_image_variables(project)),
            marketing: true
          )

        socket =
          socket
          |> assign(:project, project)
          |> assign(:period_days, Overdrive.period_days())
          |> assign(:card_image_url, image_url)
          |> assign(:head_title, dgettext("marketing", "%{name} in Overdrive", name: project.name))
          |> assign(:head_description, project.description)
          |> assign(:head_image, image_url)
          |> assign(:head_twitter_card, "summary_large_image")

        {:ok, socket}

      {:error, :not_found} ->
        raise NotFoundError
    end
  end

  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
    {:noreply, assign(socket, :current_path, current_path)}
  end
end
