defmodule TuistOpsWeb.GrantHTML do
  @moduledoc """
  Noora-styled pages for the operator project-access flow: the reason
  form, the admin "waiting for approval" page, and a generic error page.
  """
  use TuistOpsWeb, :html

  attr :subject, :string, required: true
  attr :account, :string, required: true
  attr :return_to, :string, required: true
  attr :tier, :string, default: "read"
  attr :error, :string, default: nil

  def new(assigns) do
    ~H"""
    <div class="ops-centered">
      <div class="ops-page__header">
        <h1 class="ops-page__title">Request project access</h1>
        <p class="ops-page__subtitle">
          Tell us why you need to access this customer's project. The reason is recorded and auditable.
        </p>
      </div>

      <.card icon="lock" title={"Access #{@account}"}>
        <.card_section>
          <p class="ops-muted">Signed in as <strong>{@subject}</strong></p>

          <form method="post" action="/grants" class="ops-form">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" name="account_handle" value={@account} />
            <input type="hidden" name="return_to" value={@return_to} />

            <.select id="tier" name="tier" label="Access level" value={@tier}>
              <:item value="read" label="Read — view the dashboard (granted immediately)" />
              <:item value="admin" label="Admin — act as an admin (needs Slack approval)" />
            </.select>

            <.text_input
              id="ttl_minutes"
              name="ttl_minutes"
              type="basic"
              input_type="number"
              label="Duration (minutes)"
              value="30"
              min="1"
            />

            <.text_area
              id="reason"
              name="reason"
              label="Reason"
              placeholder="e.g. investigating a failing build reported in ticket #123"
              rows={3}
              max_length={500}
              show_character_count={false}
              required
              show_required
              error={@error}
            />

            <div class="ops-form__actions">
              <.button variant="primary" label="Continue" />
            </div>
          </form>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :account, :string, required: true
  attr :state, :atom, default: :pending

  def pending(assigns) do
    ~H"""
    <div class="ops-centered">
      <div class="ops-page__header">
        <h1 class="ops-page__title">Waiting for approval</h1>
        <p class="ops-page__subtitle">Admin access to a customer org needs a second human.</p>
      </div>

      <.card icon="clock_hour_4" title={"Access #{@account}"}>
        <.card_section>
          <p class="ops-muted">
            Your request for <strong>admin</strong>
            access is pending. A second person needs to approve it in Slack.
          </p>
          <p class="ops-hint">{state_message(@state)}</p>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp state_message(:denied), do: "Request denied."
  defp state_message(:expired), do: "Request expired. Start again."
  defp state_message(_), do: "Waiting… this page checks for approval automatically."

  attr :title, :string, required: true
  attr :message, :string, required: true

  def error(assigns) do
    ~H"""
    <div class="ops-centered">
      <div class="ops-page__header">
        <h1 class="ops-page__title">{@title}</h1>
      </div>

      <.card icon="alert_triangle" title={@title}>
        <.card_section>
          <p class="ops-muted">{@message}</p>
        </.card_section>
      </.card>
    </div>
    """
  end
end
