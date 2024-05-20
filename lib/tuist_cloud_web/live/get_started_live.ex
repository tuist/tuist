defmodule TuistCloudWeb.GetStartedLive do
  use TuistCloudWeb, :live_view

  alias TuistCloud.Accounts

  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    account = Accounts.get_account_from_user(user)

    {
      :ok,
      socket
      |> assign(:selected_account, account)
    }
  end

  attr(:title, :string, required: true)
  attr(:subtitle, :string, required: true)
  attr(:link, :string, required: true)
  attr(:link_text, :string, required: true)
  slot(:icon, required: true)

  def more_card(assigns) do
    ~H"""
    <.card>
      <div class="get-started__page__more-card__icon">
        <%= render_slot(@icon) %>
      </div>
      <.stack gap="sm" class="get-started__page__more-card__header">
        <p class="text--extraLarge color--text-primary font--semibold">
          <%= @title %>
        </p>
        <p class="text--medium color--text-tertiary font--regular">
          <%= @subtitle %>
        </p>
      </.stack>
      <a href={@link} target="_blank" class="get-started__page__more-card__link">
        <span class="font--semibold"><%= @link_text %></span>
        <.arrow_right />
      </a>
    </.card>
    """
  end
end
