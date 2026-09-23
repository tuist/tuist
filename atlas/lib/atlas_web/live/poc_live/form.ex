defmodule AtlasWeb.POCLive.Form do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Accounts
  alias Atlas.Accounts.POCs
  alias Atlas.Accounts.POCs.POC

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    poc =
      case socket.assigns.live_action do
        :new -> %POC{status: "draft", hosting: "unknown"}
        :edit -> POCs.get_poc!(params["id"])
      end

    if POCs.can_manage?(user) do
      accounts = Accounts.list_accounts(sort_by: "name", sort_order: "asc")

      {:ok,
       socket
       |> assign(:page_title, if(socket.assigns.live_action == :new, do: "New POC", else: "Edit POC"))
       |> assign(:poc, poc)
       |> assign(:accounts, accounts)
       |> assign(:status_options, POC.statuses())
       |> assign(:hosting_options, POC.hosting_values())
       |> assign_form(POCs.change_poc(poc))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only operators can manage POCs.")
       |> redirect(to: ~p"/commercial/sales/pocs")}
    end
  end

  @impl true
  def handle_event("validate", %{"poc" => params}, socket) do
    changeset =
      socket.assigns.poc
      |> POCs.change_poc(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"poc" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> POCs.create_poc(params, socket.assigns.current_user)
        :edit -> POCs.update_poc(socket.assigns.poc, params, socket.assigns.current_user)
      end

    case result do
      {:ok, poc} ->
        {:noreply,
         socket
         |> put_flash(:info, "POC saved.")
         |> push_navigate(to: ~p"/commercial/sales/pocs/#{poc.id}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only operators can manage POCs.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :poc))

  @impl true
  def render(assigns) do
    ~H"""
    <section id="poc-form">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{if @live_action == :new, do: "New POC", else: "Edit POC"}</h1>
          <p>Capture the POC scope. Structured fields populate the public brief.</p>
        </div>
      </div>
      <.card icon="checkup_list" title="Details">
        <.card_section>
          <.form for={@form} id="poc-form-form" phx-change="validate" phx-submit="save">
            <.text_input
              field={@form[:title]}
              label="Title"
              placeholder="Q3 platform team evaluation"
            />
            <div data-part="select-field">
              <span>Account</span>
              <.select
                id="poc-account-id"
                name={@form[:account_id].name}
                value={to_string(@form[:account_id].value)}
                label="Select account"
              >
                <:item
                  :for={account <- @accounts}
                  value={account.id}
                  label={account.name}
                />
              </.select>
            </div>
            <div data-part="select-field">
              <span>Status</span>
              <.select
                id="poc-status"
                name={@form[:status].name}
                value={to_string(@form[:status].value)}
                label="Select status"
              >
                <:item
                  :for={status <- @status_options}
                  value={status}
                  label={humanize(status)}
                />
              </.select>
            </div>
            <div data-part="select-field">
              <span>Hosting</span>
              <.select
                id="poc-hosting"
                name={@form[:hosting].name}
                value={to_string(@form[:hosting].value)}
                label="Select hosting"
              >
                <:item
                  :for={hosting <- @hosting_options}
                  value={hosting}
                  label={humanize(hosting)}
                />
              </.select>
            </div>
            <.text_input
              id="poc-starts-on"
              field={@form[:starts_on]}
              input_type="date"
              label="Starts on"
              show_suffix={false}
            />
            <.text_input
              id="poc-ends-on"
              field={@form[:ends_on]}
              input_type="date"
              label="Ends on"
              show_suffix={false}
            />
            <.text_area
              field={@form[:summary]}
              label="Summary"
              placeholder="One or two sentences the customer will read at the top of the brief."
              rows={3}
              max_length={8000}
            />
            <.text_input
              field={@form[:brand_accent_color]}
              label="Brand accent color"
              placeholder="#1a2b3c"
            />
            <.text_input
              field={@form[:brand_logo_url]}
              label="Brand logo URL"
              placeholder="https://…"
            />
            <div data-part="form-actions">
              <.button
                label={if @live_action == :new, do: "Create POC", else: "Save changes"}
                size="medium"
                variant="primary"
                type="submit"
              />
            </div>
          </.form>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp humanize(value) when is_binary(value) do
    value |> String.replace("_", " ") |> String.capitalize()
  end

  defp humanize(value), do: to_string(value)
end
