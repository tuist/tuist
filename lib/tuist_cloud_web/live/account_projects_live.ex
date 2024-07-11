defmodule TuistCloudWeb.AccountProjectsLive do
  alias TuistCloud.Projects
  use TuistCloudWeb, :live_view

  def mount(_params, _session, socket) do
    selected_account = socket.assigns[:selected_account]
    current_user = socket.assigns[:current_user]

    if not TuistCloud.Authorization.can(current_user, :read, selected_account, :projects) do
      raise TuistCloudWeb.Errors.NotFoundError,
            gettext("The page you are looking for doesn't exist or has been moved.")
    end

    projects =
      selected_account |> Projects.get_all_project_accounts() |> Enum.map(&Map.get(&1, :project))

    {:ok,
     socket
     |> assign(:projects, projects)
     |> assign(:page_title, "#{gettext("Projects")} · #{selected_account.name} · Tuist")}
  end

  attr(:title, :string, required: true)
  attr(:subtitle, :string, required: true)
  attr(:link, :string, required: true)
  attr(:link_text, :string, required: true)
  slot(:icon, required: true)

  def more_card(assigns) do
    ~H"""
    <.card>
      <div class="account__projects__get-started__more-card__icon">
        <%= render_slot(@icon) %>
      </div>
      <.stack gap="sm" class="account__projects__get-started__more-card__header">
        <p class="text--extraLarge color--text-primary font--semibold">
          <%= @title %>
        </p>
        <p class="text--medium color--text-tertiary font--regular">
          <%= @subtitle %>
        </p>
      </.stack>
      <a href={@link} target="_blank" class="account__projects__get-started__more-card__link">
        <span class="font--semibold"><%= @link_text %></span>
        <.arrow_right_icon />
      </a>
    </.card>
    """
  end
end
