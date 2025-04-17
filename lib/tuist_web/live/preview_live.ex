defmodule TuistWeb.PreviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use TuistWeb.Noora

  import TuistWeb.Components.Terminal
  import TuistWeb.Previews.PlatformIcon
  import TuistWeb.Previews.RanByBadge

  alias Tuist.Authorization
  alias Tuist.Previews
  alias TuistWeb.Errors.NotFoundError

  def mount(%{"id" => preview_id} = _params, _session, socket) do
    preview =
      get_current_preview(preview_id)

    layout =
      if TuistWeb.Authentication.authenticated?(socket.assigns) do
        {TuistWeb.Layouts, :project}
      else
        false
      end

    if not Authorization.can(
         socket.assigns.current_user,
         :read,
         preview
       ) do
      raise NotFoundError,
            "Preview not found."
    end

    user_agent = UAParser.parse(get_connect_info(socket, :user_agent))

    {
      :ok,
      socket
      |> assign(
        :head_title,
        gettext("%{display_name} · Tuist", display_name: preview.display_name)
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
    case {user_agent.os.family, preview.type} do
      {"iOS", :ipa} ->
        {String.to_atom("itms-services"),
         "//?action=download-manifest&url=#{url(~p"/#{preview.project.account.name}/#{preview.project.name}/previews/#{preview.id}/manifest.plist")}"}

      {"iOS", _} ->
        nil

      _ ->
        {:tuist,
         "open-preview?server_url=#{TuistWeb.Endpoint.url()}&preview_id=#{preview.id}&full_handle=#{preview.project.account.name}/#{preview.project.name}"}
    end
  end

  attr :platform, :atom, required: true

  def platform_tag(assigns) do
    ~H"""
    <.tag
      label={Previews.platform_string(@platform)}
      color="neutral"
      style="light"
      icon={platform_icon_name(@platform)}
    />
    """
  end

  defp get_current_preview(preview_id) do
    case Previews.get_preview_by_id(preview_id,
           preload: [:command_event, :ran_by_account, project: [:account]]
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
