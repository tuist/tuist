defmodule TuistWeb.PreviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.Terminal
  import TuistWeb.Previews.PlatformTag
  import TuistWeb.Previews.RanByBadge

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.SHA

  def mount(%{"id" => preview_id} = _params, _session, %{assigns: %{selected_project: selected_project}} = socket) do
    preview =
      get_current_preview(preview_id)

    layout =
      if TuistWeb.Authentication.authenticated?(socket.assigns) or
           selected_project.visibility == :public do
        {TuistWeb.Layouts, :project}
      else
        false
      end

    preview = Tuist.Repo.preload(preview, :project)

    user_agent = UAParser.parse(get_connect_info(socket, :user_agent))

    {
      :ok,
      socket
      |> assign(
        :head_title,
        dgettext("dashboard_previews", "%{display_name} · Tuist", display_name: preview.display_name)
      )
      |> assign(
        :preview,
        preview
      )
      |> assign(
        :user_agent,
        user_agent
      )
      |> assign(
        :run_button_href,
        run_button_href(preview, user_agent)
      )
      |> assign(
        :preview_url,
        url(~p"/#{preview.project.account.name}/#{preview.project.name}/previews/#{preview.id}")
      ),
      layout: layout
    }
  end

  attr(:title, :string, required: true)
  attr(:value, :string, required: true)

  def preview_metadata_item(assigns) do
    ~H"""
    <div class="preview__extra-metadata-item">
      <p class="preview__extra-metadata-item__title">
        {@title}
      </p>
      <p class="preview__extra-metadata-item__value">
        {@value}
      </p>
    </div>
    """
  end

  defp run_button_href(preview, user_agent) do
    case {user_agent.os.family, AppBuilds.latest_ipa_app_build_for_preview(preview)} do
      {"iOS", %AppBuild{}} ->
        {String.to_atom("itms-services"),
         "//?action=download-manifest&url=#{url(~p"/#{preview.project.account.name}/#{preview.project.name}/previews/#{preview.id}/manifest.plist")}"}

      {"iOS", _} ->
        nil

      _ ->
        {:tuist,
         "open-preview?server_url=#{TuistWeb.Endpoint.url()}&preview_id=#{preview.id}&full_handle=#{preview.project.account.name}/#{preview.project.name}"}
    end
  end

  def handle_event(
        "delete_preview",
        _params,
        %{assigns: %{preview: preview, selected_project: selected_project}} = socket
      ) do
    AppBuilds.delete_preview!(preview)

    {
      :noreply,
      push_navigate(socket,
        to: ~p"/#{selected_project.account.name}/#{selected_project.name}/previews"
      )
    }
  end

  defp get_current_preview(preview_id) do
    case AppBuilds.preview_by_id(preview_id,
           preload: [:created_by_account, :app_builds, project: [:account]]
         ) do
      {:error, :not_found} ->
        raise NotFoundError, "Preview not found."

      {:ok, preview} ->
        preview

      {:error, _} ->
        raise NotFoundError,
              "Preview not found."
    end
  end
end
