defmodule AtlasWeb.ProjectLive.Alerts do
  @moduledoc false

  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import Phoenix.LiveView

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Users

  def attach(socket) do
    user = socket.assigns.current_user
    socket = assign(socket, :can_view_alerts?, Users.has_scope?(user, "engineering:read"))

    if socket.assigns.can_view_alerts? do
      socket
      |> assign(:can_manage?, Users.has_scope?(user, "engineering:write"))
      |> reset_form()
      |> load_rules()
      |> attach_hook(:project_alerts, :handle_event, &handle_event/3)
    else
      socket
    end
  end

  defp handle_event("new_rule", _params, socket) do
    if can_manage?(socket) do
      {:halt, socket |> reset_form() |> push_event("open-modal", %{id: "error-alert-modal"})}
    else
      {:halt, socket}
    end
  end

  defp handle_event("validate_rule", %{"rule" => params}, socket) do
    if can_manage?(socket) do
      changeset = Alerts.change_rule(socket.assigns.editing_rule, clean_params(params))
      {:halt, assign_form(socket, %{changeset | action: :validate})}
    else
      {:halt, socket}
    end
  end

  defp handle_event("save_rule", %{"rule" => params}, socket) do
    if can_manage?(socket) do
      attrs = clean_params(params)

      result =
        case socket.assigns.editing_rule do
          %Rule{id: nil} -> Alerts.create_rule(socket.assigns.project, Map.put_new(attrs, "enabled", false))
          rule -> Alerts.update_rule(rule, attrs)
        end

      case result do
        {:ok, _rule} ->
          {:halt,
           socket
           |> load_rules()
           |> reset_form()
           |> put_flash(:info, gettext("Alert rule saved."))
           |> push_event("close-modal", %{id: "error-alert-modal"})}

        {:error, changeset} ->
          {:halt, assign_form(socket, changeset)}
      end
    else
      {:halt, socket}
    end
  end

  defp handle_event("edit_rule", %{"id" => id}, socket) do
    with true <- can_manage?(socket), {:ok, rule} <- project_rule(socket, id) do
      {:halt,
       socket
       |> assign(:editing_rule, rule)
       |> assign_form(Alerts.change_rule(rule))
       |> push_event("open-modal", %{id: "error-alert-modal"})}
    else
      _ -> {:halt, socket}
    end
  end

  defp handle_event("toggle_rule", %{"id" => id}, socket) do
    with true <- can_manage?(socket),
         {:ok, rule} <- project_rule(socket, id),
         {:ok, _} <- Alerts.update_rule(rule, %{enabled: not rule.enabled}) do
      {:halt, load_rules(socket)}
    else
      _ -> {:halt, socket}
    end
  end

  defp handle_event("cancel_rule", _params, socket),
    do: {:halt, socket |> reset_form() |> push_event("close-modal", %{id: "error-alert-modal"})}

  defp handle_event("rule_modal_open_change", %{"open" => false}, socket), do: {:halt, reset_form(socket)}
  defp handle_event("rule_modal_open_change", _params, socket), do: {:halt, socket}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  def section(assigns) do
    ~H"""
    <section id="project-alerts">
      <.card title={gettext("Error alerts")} icon="bell">
        <:actions>
          <.rule_modal :if={@can_manage?} form={@form} editing_rule={@editing_rule} />
        </:actions>
        <.card_section data-part="error-alerts-card">
          <.table :if={!@rules_empty?} id="error-alert-rules" rows={@streams.rules}>
            <:col :let={{_id, rule}} label={gettext("Rule")}>
              <.text_and_description_cell label={rule.name} description={rule_description(rule)} />
            </:col>
            <:col :let={{_id, rule}} label={gettext("Destination")}>
              <.text_cell label={
                if rule.destination_type == :webhook,
                  do: gettext("Webhook configured"),
                  else: rule.slack_channel_id
              } />
            </:col>
            <:col :let={{_id, rule}} label={gettext("Status")}>
              <.badge
                label={if rule.enabled, do: gettext("Enabled"), else: gettext("Disabled")}
                color={if rule.enabled, do: "success", else: "neutral"}
              />
            </:col>
            <:col :let={{_id, rule}} label="">
              <.button_cell>
                <:button :if={@can_manage?}>
                  <.button
                    label={gettext("Edit")}
                    phx-click="edit_rule"
                    phx-value-id={rule.id}
                    variant="secondary"
                    size="small"
                  />
                </:button>
                <:button :if={@can_manage?}>
                  <.button
                    label={if rule.enabled, do: gettext("Disable"), else: gettext("Enable")}
                    phx-click="toggle_rule"
                    phx-value-id={rule.id}
                    variant="secondary"
                    size="small"
                  />
                </:button>
              </.button_cell>
            </:col>
          </.table>
          <.table :if={@rules_empty?} id="error-alert-rules-empty" rows={[]}>
            <:col label={gettext("Rule")} />
            <:empty_state>
              <.table_empty_state
                icon="bell"
                title={gettext("No error alert rules")}
                subtitle={
                  gettext("Create a disabled rule, then enable it when you are ready to send alerts.")
                }
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :form, :any, required: true
  attr :editing_rule, :any, required: true

  defp rule_modal(assigns) do
    ~H"""
    <.modal
      id="error-alert-modal"
      title={if @editing_rule.id, do: gettext("Edit alert rule"), else: gettext("Add alert rule")}
      description={gettext("Choose which errors to monitor and where to send alerts.")}
      header_type="icon"
      header_size="large"
      on_dismiss="cancel_rule"
      on_open_change="rule_modal_open_change"
      data-part="error-alert-modal"
    >
      <:header_icon><.bell /></:header_icon>
      <:trigger :let={attrs}>
        <.button
          id="add-error-alert-rule"
          label={gettext("Add alert rule")}
          variant="secondary"
          size="medium"
          type="button"
          phx-click="new_rule"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <.form
        id="error-alert-form"
        for={@form}
        phx-change="validate_rule"
        phx-submit="save_rule"
        data-part="form"
      >
        <.text_input field={@form[:name]} label={gettext("Name")} required />
        <.rule_select
          field={@form[:trigger]}
          label={gettext("Trigger")}
          options={[
            {"event_spike", gettext("Error spike in a time window")},
            {"event_rate", gettext("Cumulative events since last notification")},
            {"regression", gettext("Resolved issue regressed")}
          ]}
        />
        <.rule_select
          field={@form[:tier]}
          label={gettext("Tier")}
          options={[{"attention", gettext("Attention")}, {"incident", gettext("Incident")}]}
        />
        <.text_input
          field={@form[:environment]}
          label={gettext("Exact environment")}
          hint={
            gettext("Use the SDK's exact environment value, for example prod rather than production.")
          }
        />
        <.rule_select
          field={@form[:min_level]}
          label={gettext("Minimum level")}
          options={Enum.map(Rule.levels(), &{to_string(&1), to_string(&1)})}
        />
        <.text_input
          :if={@form[:trigger].value not in [:regression, "regression"]}
          field={@form[:threshold_event_count]}
          input_type="number"
          min={1}
          label={gettext("Event count threshold")}
        />
        <.text_input
          :if={@form[:trigger].value in [:event_spike, "event_spike"]}
          field={@form[:threshold_window_minutes]}
          input_type="number"
          min={1}
          max={60}
          label={gettext("Window (minutes)")}
        />
        <.text_input
          field={@form[:cooldown_minutes]}
          input_type="number"
          min={0}
          label={gettext("Cooldown (minutes)")}
        />
        <.rule_select
          field={@form[:destination_type]}
          label={gettext("Destination")}
          options={[{"slack", gettext("Slack")}, {"webhook", gettext("Webhook")}]}
        />
        <.text_input
          :if={@form[:destination_type].value in [:slack, "slack"]}
          field={@form[:slack_channel_id]}
          label={gettext("Slack channel ID")}
        />
        <.text_input
          :if={@form[:destination_type].value in [:webhook, "webhook"]}
          field={@form[:webhook_url]}
          input_type="password"
          autocomplete="off"
          label={gettext("Webhook URL")}
          hint={
            gettext(
              "Leave blank when editing to keep the saved URL. URLs and signing secrets are never displayed."
            )
          }
        />
        <p data-part="alert-rule-hint">
          {gettext(
            "New rules start disabled. Preview historical windows, then use Enable in the rules table."
          )}
        </p>
      </.form>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={gettext("Cancel")}
              type="button"
              phx-click="cancel_rule"
              variant="secondary"
              size="medium"
            />
          </:action>
          <:action>
            <.button
              label={gettext("Save rule")}
              type="submit"
              form="error-alert-form"
              variant="primary"
              size="medium"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :field, :any, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true

  defp rule_select(assigns) do
    ~H"""
    <div data-part="select-field">
      <span>{@label}</span>
      <.select id={@field.id} name={@field.name} value={to_string(@field.value || "")} label={@label}>
        <:item :for={{value, label} <- @options} value={value} label={label} />
      </.select>
    </div>
    """
  end

  defp can_manage?(socket), do: Users.has_scope?(socket.assigns.current_user, "engineering:write")

  defp project_rule(socket, id) do
    case Alerts.get_rule(id) do
      {:ok, %Rule{project_id: project_id} = rule} when project_id == socket.assigns.project.id -> {:ok, rule}
      _ -> {:error, :not_found}
    end
  end

  defp clean_params(params) do
    params = Map.drop(params, ["project_id", "webhook_signing_secret", "source"])
    if params["webhook_url"] in [nil, ""], do: Map.delete(params, "webhook_url"), else: params
  end

  defp reset_form(socket) do
    rule = %Rule{
      project_id: socket.assigns.project.id,
      trigger: :event_spike,
      enabled: false,
      min_level: :error,
      threshold_window_minutes: 5
    }

    socket |> assign(:editing_rule, rule) |> assign_form(Alerts.change_rule(rule))
  end

  defp assign_form(socket, changeset) do
    changeset = %{changeset | data: %{changeset.data | webhook_url: nil, webhook_signing_secret: nil}}
    form = to_form(changeset, as: :rule)

    errors =
      Enum.map(form.errors, fn {field, error} -> {field, {AtlasWeb.CoreComponents.translate_error(error), []}} end)

    assign(socket, :form, %{form | errors: errors})
  end

  defp load_rules(socket) do
    rules = Alerts.list_rules_for_project(socket.assigns.project)
    socket |> assign(:rules_empty?, rules == []) |> stream(:rules, rules, reset: true)
  end

  defp rule_description(%Rule{trigger: :event_spike} = rule),
    do:
      "#{rule.tier} · #{rule.environment} · #{rule.threshold_event_count} / #{rule.threshold_window_minutes} min · #{rule.cooldown_minutes} min cooldown"

  defp rule_description(rule),
    do:
      "#{rule.tier} · #{rule.environment || "all environments"} · #{rule.trigger} · #{rule.cooldown_minutes} min cooldown"
end
