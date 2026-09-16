defmodule AtlasWeb.FeatureInterestsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Noora.Time

  alias Atlas.Accounts
  alias Atlas.Audit

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Feature interest"))
     |> assign_new_feature_form()
     |> clear_feature_interest_context_modal()}
  end

  def handle_event("create_feature_interest", %{"feature_interest" => params}, socket) do
    result =
      Audit.with_context(%{actor: socket.assigns.current_user, interface: "dashboard"}, fn ->
        Accounts.create_feature_interest(params, socket.assigns.current_user)
      end)

    case result do
      {:ok, interest} ->
        {:noreply,
         socket
         |> assign_new_feature_form()
         |> push_navigate(to: ~p"/sales/feature-interests/#{interest.id}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:new_feature_form, to_form(changeset, as: "feature_interest"))
         |> push_event("open-modal", %{id: "new-feature-interest-modal"})}
    end
  end

  def handle_event("close_new_feature_interest_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_new_feature_form()
     |> push_event("close-modal", %{id: "new-feature-interest-modal"})}
  end

  def handle_event("open_feature_interest_context_modal", %{"id" => id}, socket) do
    case find_feature_interest_account(socket.assigns.interest.accounts, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Feature interest record not found."))}

      interest_account ->
        {:noreply,
         socket
         |> assign_feature_interest_context_modal(interest_account)
         |> push_event("open-modal", %{id: "feature-interest-context-modal"})}
    end
  end

  def handle_event("close_feature_interest_context_modal", _params, socket) do
    {:noreply,
     socket
     |> clear_feature_interest_context_modal()
     |> push_event("close-modal", %{id: "feature-interest-context-modal"})}
  end

  def handle_event("save_feature_interest_context", %{"feature_interest_context" => params}, socket) do
    case socket.assigns.selected_feature_interest_account do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Feature interest record not found."))}

      interest_account ->
        result =
          Audit.with_context(%{actor: socket.assigns.current_user, interface: "dashboard"}, fn ->
            Accounts.update_feature_interest_notes(interest_account, params, socket.assigns.current_user)
          end)

        case result do
          {:ok, _updated_interest_account} ->
            {:noreply,
             socket
             |> clear_feature_interest_context_modal()
             |> push_patch(to: ~p"/sales/feature-interests/#{socket.assigns.interest.id}")
             |> push_event("close-modal", %{id: "feature-interest-context-modal"})}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> assign(
               :feature_interest_context_form,
               to_form(changeset, as: "feature_interest_context")
             )
             |> push_event("open-modal", %{id: "feature-interest-context-modal"})}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> clear_feature_interest_context_modal()
             |> put_flash(:error, gettext("Feature interest record not found."))
             |> push_event("close-modal", %{id: "feature-interest-context-modal"})}
        end
    end
  end

  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index ->
        {:noreply, assign(socket, :interests, Accounts.list_feature_interests())}

      :show ->
        case Accounts.get_feature_interest(params["id"]) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Feature interest not found."))
             |> push_navigate(to: ~p"/sales/feature-interests")}

          interest ->
            {:noreply, socket |> assign(:page_title, interest.title) |> assign(:interest, interest)}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <div id="feature-interests" data-part="feature-interests-page">
      <%= case @live_action do %>
        <% :index -> %>
          <.index_view interests={@interests} new_feature_form={@new_feature_form} />
        <% :show -> %>
          <.show_view
            interest={@interest}
            selected_feature_interest_account={@selected_feature_interest_account}
            feature_interest_context_form={@feature_interest_context_form}
          />
      <% end %>
    </div>
    """
  end

  attr :interests, :list, required: true
  attr :new_feature_form, :map, required: true

  defp index_view(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{gettext("Feature interest")}</h1>
        <p data-part="description">
          {gettext(
            "Requests recorded from account timeline events, grouped by the capability they need."
          )}
        </p>
      </div>
      <div data-part="actions">
        <.modal
          id="new-feature-interest-modal"
          title={gettext("New feature")}
          description={
            gettext("Add a capability to the registry before an account has asked for it.")
          }
          header_type="icon"
          header_size="small"
          on_dismiss="close_new_feature_interest_modal"
        >
          <:header_icon><.message_circle /></:header_icon>
          <:trigger :let={modal_attrs}>
            <.button
              id="new-feature-interest-button"
              label={gettext("New feature")}
              size="medium"
              type="button"
              {modal_attrs}
            >
              <:icon_left><.icon name="plus" /></:icon_left>
            </.button>
          </:trigger>
          <div data-part="feature-interest-modal-content">
            <.form
              id="new-feature-interest-form"
              for={@new_feature_form}
              phx-submit="create_feature_interest"
            >
              <.text_input
                id="new-feature-interest-title-input"
                field={@new_feature_form[:title]}
                type="basic"
                label={gettext("Capability")}
                placeholder={gettext("Remote build runners")}
                required
                show_required
                show_suffix={false}
              />
            </.form>
          </div>
          <:footer>
            <.modal_footer>
              <:action>
                <.button
                  label={gettext("Cancel")}
                  variant="secondary"
                  size="small"
                  type="button"
                  phx-click="close_new_feature_interest_modal"
                />
              </:action>
              <:action>
                <.button
                  id="new-feature-interest-submit"
                  label={gettext("Create feature")}
                  size="small"
                  type="submit"
                  form="new-feature-interest-form"
                />
              </:action>
            </.modal_footer>
          </:footer>
        </.modal>
      </div>
    </div>

    <.card
      title={gettext("Requested capabilities")}
      icon="message_circle"
      data-part="feature-interests-card"
    >
      <.card_section data-part="feature-interests-table-section">
        <.table
          id="feature-interests-table"
          rows={@interests}
          row_navigate={fn interest -> ~p"/sales/feature-interests/#{interest.id}" end}
        >
          <:col :let={interest} label={gettext("Capability")}>
            <.text_and_description_cell
              label={interest.title}
              description={status_label(interest.status)}
            />
          </:col>
          <:col :let={interest} label={gettext("Interested accounts")}>
            <.badge_cell label={Integer.to_string(interest.interest_count)} color="information" />
          </:col>
          <:col :let={interest} label={gettext("Last observed")}>
            <.text_cell label={last_observed_label(interest.last_interested_at)} />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="message_circle"
              title={gettext("No feature interest yet")}
              subtitle={
                gettext("Record a request from an account timeline event to start the register.")
              }
            />
          </:empty_state>
        </.table>
      </.card_section>
    </.card>
    """
  end

  attr :interest, :map, required: true
  attr :selected_feature_interest_account, :map, default: nil
  attr :feature_interest_context_form, :map, default: nil

  defp show_view(assigns) do
    ~H"""
    <div data-part="feature-interest-back-action">
      <.button
        id="feature-interests-back-button"
        label={gettext("Feature interest")}
        variant="secondary"
        size="medium"
        navigate={~p"/sales/feature-interests"}
      >
        <:icon_left><.icon name="arrow_left" /></:icon_left>
      </.button>
    </div>

    <div data-part="header">
      <div data-part="text">
        <h1 data-part="title">{@interest.title}</h1>
        <p data-part="description">
          {ngettext(
            "%{count} account has shown interest.",
            "%{count} accounts have shown interest.",
            @interest.interest_count,
            count: @interest.interest_count
          )}
        </p>
      </div>
      <.badge label={status_label(@interest.status)} color="information" style="light-fill" />
    </div>

    <.card
      title={gettext("Interested accounts")}
      icon="building"
      data-part="feature-interest-accounts-card"
    >
      <.card_section data-part="feature-interest-accounts-section">
        <div id="feature-interest-accounts" data-part="feature-interest-accounts-list">
          <div
            :for={interest_account <- @interest.accounts}
            id={"feature-interest-account-#{interest_account.id}"}
            data-part="feature-interest-account"
          >
            <div data-part="feature-interest-account-heading">
              <.link
                id={"feature-interest-account-link-#{interest_account.id}"}
                navigate={~p"/sales/accounts/#{interest_account.account.id}"}
                data-part="feature-interest-account-name"
              >
                {interest_account.account.name}
              </.link>
              <span data-part="feature-interest-account-time">
                <.time time={interest_account.last_interested_at} />
              </span>
            </div>
            <p data-part="feature-interest-account-summary">{interest_account.summary}</p>
            <p :if={interest_account.notes} data-part="feature-interest-account-notes">
              <span data-part="feature-interest-account-notes-label">
                {gettext("Account context")}
              </span>
              {interest_account.notes}
            </p>
            <.link
              :if={interest_account.account_event}
              id={"feature-interest-source-#{interest_account.id}"}
              navigate={
                "/sales/accounts/#{interest_account.account.id}#timeline-event-#{interest_account.account_event.id}"
              }
              data-part="feature-interest-source"
            >
              {gettext("Open source event")}
            </.link>
            <.link
              :if={is_nil(interest_account.account_event) && interest_account.support_thread}
              id={"feature-interest-source-#{interest_account.id}"}
              navigate={~p"/support/#{interest_account.support_thread.id}"}
              data-part="feature-interest-source"
            >
              {gettext("Open source conversation")}
            </.link>
            <div data-part="feature-interest-account-actions">
              <.button
                id={"edit-feature-interest-context-#{interest_account.id}"}
                label={gettext("Edit context")}
                variant="secondary"
                size="small"
                type="button"
                phx-click="open_feature_interest_context_modal"
                phx-value-id={interest_account.id}
              />
            </div>
          </div>
        </div>
        <p
          :if={@interest.accounts == []}
          id="feature-interest-accounts-empty"
          data-part="feature-interest-empty"
        >
          {gettext(
            "No account has shown interest yet. Add context from an account timeline event when evidence arrives."
          )}
        </p>
      </.card_section>
    </.card>

    <.modal
      :if={@selected_feature_interest_account}
      id="feature-interest-context-modal"
      title={gettext("Edit account context")}
      description={
        gettext("Capture the account's current solution, pain points, and other internal context.")
      }
      header_type="icon"
      header_size="small"
      on_dismiss="close_feature_interest_context_modal"
    >
      <:header_icon><.message_circle /></:header_icon>
      <:trigger :let={modal_attrs}>
        <button id="feature-interest-context-modal-trigger" type="button" hidden {modal_attrs}>
        </button>
      </:trigger>
      <div data-part="feature-interest-modal-content">
        <.form
          id="feature-interest-context-form"
          for={@feature_interest_context_form}
          phx-submit="save_feature_interest_context"
        >
          <.text_area
            id="feature-interest-context-input"
            field={@feature_interest_context_form[:notes]}
            label={gettext("Account context")}
            hint={
              gettext("For example, record the current solution, pain points, or decision criteria.")
            }
            rows={6}
            max_length={2000}
          />
        </.form>
      </div>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              variant="secondary"
              size="small"
              type="button"
              phx-click="close_feature_interest_context_modal"
            />
          </:action>
          <:action>
            <.button
              id="save-feature-interest-context-submit"
              label={gettext("Save context")}
              size="small"
              type="submit"
              form="feature-interest-context-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp status_label("open"), do: gettext("Open")
  defp status_label("planned"), do: gettext("Planned")
  defp status_label("shipped"), do: gettext("Shipped")
  defp status_label("declined"), do: gettext("Declined")
  defp status_label(_status), do: gettext("Open")

  defp last_observed_label(nil), do: "-"
  defp last_observed_label(date_time), do: Calendar.strftime(date_time, "%b %d, %Y")

  defp assign_new_feature_form(socket) do
    assign(socket, :new_feature_form, to_form(Accounts.change_feature_interest_definition(), as: "feature_interest"))
  end

  defp find_feature_interest_account(interests, id) do
    Enum.find(interests, &(&1.id == id))
  end

  defp assign_feature_interest_context_modal(socket, interest_account) do
    socket
    |> assign(:selected_feature_interest_account, interest_account)
    |> assign(
      :feature_interest_context_form,
      to_form(Accounts.change_feature_interest_notes(interest_account), as: "feature_interest_context")
    )
  end

  defp clear_feature_interest_context_modal(socket) do
    socket
    |> assign(:selected_feature_interest_account, nil)
    |> assign(:feature_interest_context_form, nil)
  end
end
