defmodule AtlasWeb.ProjectLive.Alerts do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Atlas.Users

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    with true <- Users.has_scope?(user, "engineering:read"),
         {:ok, project} <- Projects.fetch_visible_project(id, user) do
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:page_title, gettext("Error alerts"))
       |> assign(:can_manage?, Users.has_scope?(user, "engineering:write"))
       |> assign(:preview_rule, nil)
       |> assign(:preview_result, nil)
       |> assign(:preview_form, to_form(%{"at" => DateTime.to_iso8601(DateTime.utc_now())}, as: :preview))
       |> reset_form()
       |> load_rules()}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found or access denied."))
         |> redirect(to: ~p"/engineering/projects")}
    end
  end

  @impl true
  def handle_event("validate_rule", %{"rule" => params}, socket) do
    if can_manage?(socket) do
      changeset = Alerts.change_rule(socket.assigns.editing_rule, clean_params(params))
      {:noreply, assign_form(socket, changeset)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_rule", %{"rule" => params}, socket) do
    if can_manage?(socket) do
      attrs = clean_params(params)

      result =
        case socket.assigns.editing_rule do
          %Rule{id: nil} -> Alerts.create_rule(socket.assigns.project, Map.put_new(attrs, "enabled", false))
          rule -> Alerts.update_rule(rule, attrs)
        end

      case result do
        {:ok, _rule} ->
          {:noreply, socket |> load_rules() |> reset_form() |> put_flash(:info, gettext("Alert rule saved."))}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit_rule", %{"id" => id}, socket) do
    with true <- can_manage?(socket), {:ok, rule} <- project_rule(socket, id) do
      {:noreply, socket |> assign(:editing_rule, rule) |> assign_form(Alerts.change_rule(rule))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_rule", %{"id" => id}, socket) do
    with true <- can_manage?(socket),
         {:ok, rule} <- project_rule(socket, id),
         {:ok, _} <- Alerts.update_rule(rule, %{enabled: not rule.enabled}) do
      {:noreply, load_rules(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_rule", _params, socket), do: {:noreply, reset_form(socket)}

  def handle_event("select_preview", %{"id" => id}, socket) do
    case project_rule(socket, id) do
      {:ok, %Rule{trigger: :event_spike} = rule} ->
        {:noreply, socket |> assign(:preview_rule, rule) |> assign(:preview_result, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("preview_rule", %{"preview" => %{"at" => at}}, socket) do
    result =
      with %Rule{id: id} <- socket.assigns.preview_rule,
           {:ok, %Rule{trigger: :event_spike} = rule} <- project_rule(socket, id),
           true <- Errors.enabled?(),
           {:ok, at, _} <- DateTime.from_iso8601(at),
           {:ok, matches} <- Alerts.spike_matches(rule, at) do
        {:ok, matches}
      else
        _ -> {:error, gettext("Could not evaluate this window. Check the time and error storage availability.")}
      end

    {:noreply, socket |> assign(:preview_result, result) |> assign(:preview_form, to_form(%{"at" => at}, as: :preview))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="project-alerts">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{gettext("Error alerts")}</h1>
            <p>{@project.name}</p>
          </div>
          <.button
            navigate={~p"/engineering/projects/#{@project.id}"}
            label={gettext("Back to project")}
            variant="secondary"
            size="medium"
          />
        </div>
        <.card title={gettext("Rules")} icon="bell">
          <.card_section>
            <.alert
              status="information"
              size="large"
              title={gettext("Incidents are declared by the receiver")}
            >
              {gettext(
                "An incident tier alone does not declare an incident. Send a webhook to Grafana IRM and route matching production incident alerts to an escalation chain with a Declare incident step. Existing Slack rules keep working independently."
              )}
            </.alert>
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
                  <:button :if={rule.trigger == :event_spike}>
                    <.button
                      label={gettext("Preview")}
                      phx-click="select_preview"
                      phx-value-id={rule.id}
                      variant="secondary"
                      size="small"
                    />
                  </:button>
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
                    gettext(
                      "Create a disabled rule, preview historical windows, then enable it explicitly."
                    )
                  }
                />
              </:empty_state>
            </.table>
          </.card_section>
        </.card>

        <.card :if={@preview_rule} title={gettext("Historical preview")} icon="history">
          <.card_section>
            <.form
              id="error-alert-preview"
              for={@preview_form}
              phx-submit="preview_rule"
              data-part="form"
            >
              <p data-part="context-text">{@preview_rule.name}</p>
              <.text_input
                field={@preview_form[:at]}
                label={gettext("Window ending at (ISO8601)")}
                required
                hint={
                  gettext(
                    "Read-only: never sends alerts. Missing retained history is not evidence of a healthy period."
                  )
                }
              />
              <.button label={gettext("Evaluate window")} variant="secondary" size="medium" />
              <.alert
                :if={match?({:error, _}, @preview_result)}
                status="error"
                size="small"
                title={elem(@preview_result, 1)}
              />
              <div
                :if={match?({:ok, _}, @preview_result)}
                id="error-alert-preview-result"
                data-part="context-text"
              >
                <p>{gettext("Matching issues: %{count}", count: length(elem(@preview_result, 1)))}</p>
                <p :for={match <- elem(@preview_result, 1)}>
                  <.link navigate={~p"/engineering/errors/#{match.issue_id}"}>{match.issue_id}</.link>
                  {gettext("%{count} events", count: match.event_count)}
                </p>
              </div>
            </.form>
          </.card_section>
        </.card>

        <.card
          :if={@can_manage?}
          title={if @editing_rule.id, do: gettext("Edit rule"), else: gettext("New rule")}
          icon="bell"
        >
          <.card_section>
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
                  gettext(
                    "Use the SDK's exact environment value, for example prod rather than production."
                  )
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
              <p data-part="context-text">
                {gettext(
                  "New rules start disabled. Preview historical windows, then use Enable in the rules table."
                )}
              </p>
              <div data-part="form-actions">
                <.button
                  :if={@editing_rule.id}
                  label={gettext("Cancel")}
                  type="button"
                  phx-click="cancel_rule"
                  variant="secondary"
                  size="medium"
                />
                <.button label={gettext("Save rule")} variant="primary" size="medium" />
              </div>
            </.form>
          </.card_section>
        </.card>
      </section>
    </Layouts.app>
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
    assign(socket, :form, to_form(changeset, as: :rule))
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
