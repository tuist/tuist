defmodule TuistWeb.ConnectLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  @impl true
  def mount(_params, _uri, socket) do
    socket =
      assign(socket,
        sidebar_enabled?: false,
        connected?: false,
        head_title: "#{dgettext("dashboard_auth", "Connect")} · Tuist"
      )

    if connected?(socket) do
      Tuist.PubSub.subscribe("projects.#{socket.assigns.selected_project.id}")
    end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="connect">
      <div data-part="header">
        <div :if={!@connected?} data-part="subtitle">
          <.connection_svg /><span>{dgettext("dashboard_auth", "Waiting for connection")}</span>
        </div>
        <div :if={@connected?} data-part="subtitle">
          <.connection_success_svg />
          <span>
            {dgettext("dashboard_auth", "Connection successful")}
          </span>
        </div>
        <div data-part="title">
          <span>{dgettext("dashboard_auth", "Connect your project to the dashboard")}</span><span>{dgettext("dashboard_auth", "using CLI")}</span>
        </div>
        <div data-part="timeline">
          <div data-part="step">
            <span data-part="title">{dgettext("dashboard_auth", "Install Tuist CLI")}</span>
            <span data-part="description">
              {dgettext("dashboard_auth", "Run the following command to install Tuist CLI.")}
            </span>
            <.terminal id="install">
              <:tab id="mise" label={dgettext("dashboard_auth", "mise")} command="mise install tuist" />
              <:tab
                id="homebrew"
                label={dgettext("dashboard_auth", "homebrew")}
                command="brew install tuist"
              />
            </.terminal>
          </div>
          <div data-part="step">
            <span data-part="title">{dgettext("dashboard_auth", "Connect your project")}</span>
            <span data-part="description">
              {dgettext("dashboard_auth", "Run this command to link your project to the dashboard.")}
            </span>
            <.terminal id="init">
              <:tab
                id="mise"
                label={dgettext("dashboard_auth", "mise")}
                command={"mise x tuist@latest -- tuist init #{@selected_account.name}/#{@selected_project.name}"}
              />
              <:tab
                id="homebrew"
                label={dgettext("dashboard_auth", "homebrew")}
                command={"tuist init #{@selected_account.name}/#{@selected_project.name}"}
              />
            </.terminal>
          </div>
          <div data-part="step">
            <span data-part="title">{dgettext("dashboard_auth", "Next steps")}</span>
            <span data-part="description">
              {dgettext(
                "dashboard_auth",
                "Explore Tuist features like binary caching and selective testing to speed up your development."
              )}
            </span>
            <.button
              variant="primary"
              label={dgettext("dashboard_auth", "Tuist documentation")}
              href="https://docs.tuist.dev/"
              target="_blank"
            >
              <:icon_right>
                <.chevron_right />
              </:icon_right>
            </.button>
          </div>
          <.line_divider text={dgettext("dashboard_auth", "OR")} />
          <div data-part="step">
            <span data-part="title">
              {dgettext("dashboard_auth", "Project Ready? Proceed to dashboard")}
            </span>
            <span data-part="description">
              {dgettext(
                "dashboard_auth",
                "Already set up your Tuist project? Skip setup and go to the dashboard."
              )}
            </span>
            <.button
              variant="secondary"
              label={dgettext("dashboard_auth", "Tuist dashboard")}
              navigate={~p"/#{@selected_account.name}/#{@selected_project.name}"}
            >
              <:icon_right>
                <.chevron_right />
              </:icon_right>
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp connection_svg(assigns) do
    ~H"""
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <g>
        <g id="plug_right">
          <path
            d="M9 9L14 14L12.5 15.5C12.1737 15.8371 11.7835 16.1059 11.3523 16.2907C10.921 16.4755 10.4573 16.5727 9.98811 16.5765C9.51894 16.5803 9.0537 16.4907 8.6195 16.3129C8.18531 16.1351 7.79084 15.8727 7.45907 15.5409C7.12731 15.2092 6.86489 14.8147 6.6871 14.3805C6.50931 13.9463 6.41971 13.4811 6.42352 13.0119C6.42733 12.5427 6.52447 12.079 6.70928 11.6477C6.8941 11.2165 7.16289 10.8263 7.5 10.5L9 9Z"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <path d="M5 18L7.5 15.5" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
          <path d="M12 8L10 10" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
          <path d="M15 11L13 13" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
        </g>

        <g id="plug_left">
          <path
            d="M14 13.9999L9 8.99994L10.5 7.49994C10.8263 7.16283 11.2165 6.89404 11.6477 6.70922C12.079 6.52441 12.5427 6.42727 13.0119 6.42346C13.4811 6.41965 13.9463 6.50925 14.3805 6.68704C14.8147 6.86482 15.2092 7.12725 15.5409 7.45901C15.8727 7.79077 16.1351 8.18525 16.3129 8.61944C16.4907 9.05364 16.5803 9.51888 16.5765 9.98805C16.5727 10.4572 16.4755 10.9209 16.2907 11.3522C16.1059 11.7834 15.8371 12.1736 15.5 12.4999L14 13.9999Z"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <path d="M15.5 7.5L18 5" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
        </g>
      </g>
    </svg>
    """
  end

  defp connection_success_svg(assigns) do
    ~H"""
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      data-state="success"
    >
      <path
        d="M8.99994 9L13.9999 14L12.4999 15.5C12.1736 15.8371 11.7834 16.1059 11.3522 16.2907C10.9209 16.4755 10.4572 16.5727 9.98805 16.5765C9.51888 16.5803 9.05364 16.4907 8.61944 16.3129C8.18525 16.1351 7.79077 15.8727 7.45901 15.5409C7.12725 15.2092 6.86482 14.8147 6.68704 14.3805C6.50925 13.9463 6.41965 13.4811 6.42346 13.0119C6.42727 12.5427 6.52441 12.079 6.70922 11.6477C6.89404 11.2165 7.16283 10.8263 7.49994 10.5L8.99994 9Z"
        fill="#E0FFE2"
        stroke="#006420"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M5 18L7.5 15.5"
        stroke="#006420"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M12 8L10 10"
        stroke="#006420"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M15 11L13 13"
        stroke="#006420"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M14 14.0001L9 9.00006L10.5 7.50006C10.8263 7.16295 11.2165 6.89416 11.6477 6.70934C12.079 6.52453 12.5427 6.42739 13.0119 6.42358C13.4811 6.41977 13.9463 6.50937 14.3805 6.68716C14.8147 6.86495 15.2092 7.12737 15.5409 7.45913C15.8727 7.7909 16.1351 8.18537 16.3129 8.61957C16.4907 9.05376 16.5803 9.519 16.5765 9.98817C16.5727 10.4573 16.4755 10.9211 16.2907 11.3523C16.1059 11.7836 15.8371 12.1737 15.5 12.5001L14 14.0001Z"
        fill="#E0FFE2"
        stroke="#006420"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M15.5 7.5L18 5"
        stroke="#006420"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :id, :string, required: true

  slot :tab do
    attr :id, :string
    attr :label, :string
    attr :command, :string
  end

  defp terminal(assigns) do
    ~H"""
    <div
      :if={Enum.any?(@tab)}
      id={@id}
      phx-hook="NooraTabs"
      class="noora-terminal"
      data-default-value={List.first(@tab).id}
    >
      <div data-part="root">
        <div data-part="list">
          <button :for={tab <- @tab} data-part="trigger" data-value={tab.id}>
            {tab.label}
          </button>
        </div>
        <div :for={tab <- @tab} data-part="content" data-tab data-value={tab.id}>
          <span>{tab.command}</span>
          <.neutral_button
            id={tab.id <> "-button"}
            size="small"
            phx-hook="Clipboard"
            data-clipboard-value={tab.command}
          >
            <.copy />
          </.neutral_button>
        </div>
      </div>
    </div>
    <div :if={Enum.empty?(@tab)} class="noora-terminal">
      <div data-part="root">
        <div data-part="content">
          <span>{@command}</span>
          <.neutral_button
            id={@id <> "-button"}
            size="small"
            phx-hook="Clipboard"
            data-clipboard-value={@command}
          >
            <.copy />
          </.neutral_button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:show, %{user: user}}, socket) do
    socket =
      if user.id == socket.assigns.current_user.id do
        assign(socket, connected?: true)
      else
        socket
      end

    {:noreply, socket}
  end
end
