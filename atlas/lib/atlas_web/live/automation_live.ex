defmodule AtlasWeb.AutomationLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.AutomationAnalytics, only: [execution_overview: 1]
  import AtlasWeb.AutomationExecution, only: [execution_observability: 1, duration_label: 1]
  import AtlasWeb.AutomationLive.Table, only: [toolbar: 1]
  import AtlasWeb.CodeBlock, only: [code_block: 1]
  import AtlasWeb.CodeEditor, only: [code_editor: 1]
  import AtlasWeb.CoreComponents, only: []
  import Noora.Time, only: [time: 1]

  alias Atlas.Automations
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.Contract
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Workflow
  alias Atlas.Users
  alias AtlasWeb.AutomationLive.Table
  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult

  @example ~s({"steps":[{"id":"context","behavior":"core.value","inputs":{"message":"Hello from Atlas"}}]})

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 5000)

    {:ok,
     socket
     |> assign(:can_write, Users.has_scope?(socket.assigns.current_user, "automation:write"))
     |> assign(:resource, nil)
     |> assign(:execution_events, [])
     |> assign(:events_meta, nil)
     |> assign(:events_page, 1)
     |> assign(:events_error, false)
     |> assign(:definition, nil)
     |> assign(:editor_open, false)
     |> assign(:pending_navigation, nil)
     |> assign(:query_params, %{})
     |> assign(:list_key, nil)
     |> assign(:analytics_days, 30)
     |> assign(:analytics_preset, "last-30-days")
     |> assign(:analytics_metric, "executions")
     |> assign(:analytics_end_date, Date.utc_today())
     |> assign(:analytics_key, nil)
     |> assign(:analytics_refreshed_at, nil)
     |> assign(:execution_analytics, AsyncResult.loading())
     |> assign(:secret, nil)
     |> assign(:types, Catalog.types())
     |> assign(:visible_types, Catalog.types())
     |> assign(:selected_type, nil)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:empty, true)
     |> assign(:records, %{})
     |> assign(:reviewing_approval, nil)
     |> assign(:form_error, nil)
     |> assign(:run_error, nil)
     |> assign(:review_error, nil)
     |> assign(:form, to_form(%{}, as: :automation))
     |> stream(:items, [])}
  end

  def handle_params(params, uri, socket) do
    section = section(socket.assigns.live_action)

    socket =
      socket
      |> assign(:section, section)
      |> assign(:secret, nil)
      |> assign(:reviewing_approval, nil)
      |> assign_analytics_params(params)
      |> assign(:uri, URI.parse(uri))
      |> assign_table_params()

    case load_detail(socket, params) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> assign(:page_title, page_heading(section, socket.assigns.resource))
         |> load_execution_events(params)
         |> maybe_assign_form()
         |> maybe_load_list(params)
         |> load_analytics()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Automation record not found."))
         |> push_navigate(to: ~p"/automation/workflows")}
    end
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 5000)
    socket = load_list(socket, Map.put(socket.assigns.query_params, "page", to_string(socket.assigns.page)))

    socket =
      if socket.assigns.live_action in [:workflow, :execution] && !socket.assigns.editor_open do
        case load_detail(socket, %{"id" => socket.assigns.resource.id}) do
          {:ok, socket} -> socket
          _ -> socket
        end
      else
        socket
      end

    socket = load_execution_events(socket, %{"events_page" => socket.assigns.events_page})
    {:noreply, refresh_analytics(socket)}
  end

  def handle_event("search_table", %{"table_search" => %{"query" => query}} = event, socket) when is_binary(query) do
    prefix = if socket.assigns.section == "behaviors" and event["table_prefix"] == "config_", do: "config_", else: ""
    key = prefix <> "q"
    query = query |> String.trim() |> String.slice(0, 120)
    params = socket.assigns.query_params |> Map.delete("page") |> Map.put(key, query)
    params = if query == "", do: Map.delete(params, key), else: params
    {:noreply, push_patch(socket, to: Table.path(socket.assigns.section, params), replace: true)}
  end

  def handle_event("add_filter", %{"value" => id}, socket) do
    if Enum.any?(socket.assigns.available_filters, &(&1.id == id)) do
      params = Filter.Operations.add_filter_to_query(id, socket, Map.delete(socket.assigns.query_params, "page"))

      {:noreply,
       socket
       |> push_patch(to: Table.path(socket.assigns.section, params))
       |> push_event("open-dropdown", %{id: "filter-#{id}-value-dropdown"})
       |> push_event("open-popover", %{id: "filter-#{id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", %{"payload_filter_id" => id} = params, socket) do
    if Enum.any?(socket.assigns.available_filters, &(&1.id == id)) and
         (is_nil(params["value"]) or is_binary(params["value"])) do
      params = Map.update(params, "value", nil, fn value -> if value, do: String.slice(value, 0, 160) end)
      query = Filter.Operations.update_filters_in_query(params, socket, Map.delete(socket.assigns.query_params, "page"))

      {:noreply,
       socket
       |> push_patch(to: Table.path(socket.assigns.section, query))
       |> push_event("close-dropdown", %{id: "all", all: true})
       |> push_event("close-popover", %{id: "filter-#{id}-value-popover"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("inspect_type", %{"reference" => reference}, socket) do
    type = Enum.find(socket.assigns.types, &(&1.reference == reference))
    {:noreply, socket |> assign(:selected_type, type) |> push_event("open-modal", %{id: "behavior-contract-modal"})}
  end

  def handle_event("close_type_contract", _, socket),
    do: {:noreply, push_event(socket, "close-modal", %{id: "behavior-contract-modal"})}

  def handle_event("type_contract_open_changed", %{"open" => false}, socket),
    do: {:noreply, assign(socket, :selected_type, nil)}

  def handle_event("type_contract_open_changed", _, socket), do: {:noreply, socket}

  def handle_event("select_analytics_metric", %{"widget" => metric}, socket)
      when metric in ["executions", "success_rate", "duration", "approvals"] do
    {:noreply, analytics_patch(socket, %{"metric" => metric})}
  end

  def handle_event("select_analytics_period", %{"days" => days}, socket) when days in ["7", "30", "90"] do
    {:noreply,
     socket
     |> assign(:analytics_end_date, Date.utc_today())
     |> analytics_patch(%{"days" => days, "end_date" => nil, "page" => "1"})}
  end

  def handle_event("analytics_period_changed", %{"preset" => "last-" <> range}, socket)
      when range in ["7-days", "30-days", "90-days"] do
    handle_event("select_analytics_period", %{"days" => String.replace_suffix(range, "-days", "")}, socket)
  end

  def handle_event(
        "analytics_period_changed",
        %{"preset" => "custom", "value" => %{"start" => first, "end" => last}},
        socket
      )
      when is_binary(first) and is_binary(last) do
    with {:ok, first} <- Date.from_iso8601(first),
         {:ok, last} <- Date.from_iso8601(last),
         days when days in 1..90 <- Date.diff(last, first) + 1,
         true <- Date.compare(last, Date.utc_today()) != :gt && first.year > 0 do
      {:noreply,
       analytics_patch(socket, %{"days" => to_string(days), "end_date" => Date.to_iso8601(last), "page" => "1"})}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Select a date range of 1 to 90 days, not later than today."))}
    end
  end

  def handle_event("analytics_period_changed", _params, socket), do: {:noreply, socket}

  def handle_event("retry_analytics", _params, socket), do: {:noreply, load_analytics(socket, true)}

  def handle_event(event, _params, socket) when event in ["select_analytics_metric", "select_analytics_period"],
    do: {:noreply, socket}

  def handle_event("open_editor", _params, socket) do
    {:noreply,
     socket
     |> assign(:editor_open, true)
     |> assign_form()
     |> push_event("open-modal", %{id: "automation-editor-modal"})}
  end

  def handle_event("close_editor", _params, socket) do
    {:noreply,
     socket
     |> assign(:editor_open, false)
     |> assign_form()
     |> push_event("close-modal", %{id: "automation-editor-modal"})}
  end

  def handle_event("editor_open_changed", %{"open" => false}, socket) do
    {:noreply,
     socket
     |> assign(:editor_open, false)
     |> assign_form()
     |> finish_navigation("automation-editor-modal")}
  end

  def handle_event("editor_open_changed", %{"open" => true}, socket), do: {:noreply, assign(socket, :editor_open, true)}

  def handle_event("change", %{"automation" => attrs}, socket) do
    {:noreply, assign(socket, form: to_form(attrs, as: :automation), form_error: nil)}
  end

  def handle_event("save", %{"automation" => attrs}, socket) do
    actor = socket.assigns.current_user

    result =
      case socket.assigns.section do
        "workflows" -> save_workflow(actor, socket.assigns.resource, attrs)
        "behaviors" -> save_behavior(actor, attrs)
        section when section in ["schedules", "webhooks"] -> save_trigger(actor, section, attrs)
        _ -> {:error, :not_allowed}
      end

    case result do
      {:ok, %Workflow{} = workflow} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Version %{number} saved.", number: workflow.published_revision.number))
         |> navigate_after_close("automation-editor-modal", ~p"/automation/workflows/#{workflow.id}")}

      {:ok, %{secret: secret}} ->
        {:noreply,
         socket
         |> assign(:secret, secret)
         |> load_list(%{})
         |> assign_form()
         |> push_event("close-modal", %{id: "automation-editor-modal"})
         |> put_flash(:info, gettext("Trigger created."))}

      {:ok, _} ->
        {:noreply,
         socket
         |> load_list(%{})
         |> assign_form()
         |> push_event("close-modal", %{id: "automation-editor-modal"})
         |> put_flash(:info, gettext("Behavior created."))}

      {:error, error} ->
        {:noreply, form_failure(socket, attrs, error)}
    end
  end

  def handle_event("open_run", _params, socket) do
    {:noreply, socket |> assign(:run_error, nil) |> push_event("open-modal", %{id: "run-workflow-modal"})}
  end

  def handle_event("close_run", _params, socket) do
    {:noreply, socket |> assign(:run_error, nil) |> push_event("close-modal", %{id: "run-workflow-modal"})}
  end

  def handle_event("run_open_changed", %{"open" => false}, socket),
    do: {:noreply, finish_navigation(socket, "run-workflow-modal")}

  def handle_event("run_open_changed", _params, socket), do: {:noreply, socket}

  def handle_event("run", %{"run" => %{"input" => input}}, socket) do
    with {:ok, input} <- object(input),
         {:ok, run} <- Automations.run_workflow(socket.assigns.current_user, socket.assigns.resource.id, input) do
      {:noreply, navigate_after_close(socket, "run-workflow-modal", ~p"/automation/executions/#{run.id}")}
    else
      {:error, error} -> {:noreply, assign(socket, :run_error, error_message(error))}
    end
  end

  def handle_event("review", %{"id" => id}, socket) do
    with :ok <- Automations.authorize(socket.assigns.current_user, :read),
         %{step_id: _} = approval <- Map.get(socket.assigns.records, id) do
      {:noreply,
       socket
       |> assign(:reviewing_approval, approval)
       |> assign(:review_error, nil)
       |> push_event("open-modal", %{id: "approval-review-modal"})}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Automation record not found."))}
    end
  end

  def handle_event("close_review", _params, socket) do
    {:noreply,
     socket
     |> assign(:reviewing_approval, nil)
     |> push_event("close-modal", %{id: "approval-review-modal"})}
  end

  def handle_event("review_open_changed", %{"open" => false}, socket),
    do: {:noreply, assign(socket, :reviewing_approval, nil)}

  def handle_event("review_open_changed", _params, socket), do: {:noreply, socket}

  def handle_event("decide", %{"id" => id, "decision" => decision}, socket) when decision in ["approved", "rejected"] do
    case Automations.decide_approval(socket.assigns.current_user, id, decision) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:reviewing_approval, nil)
         |> load_list(%{})
         |> push_event("close-modal", %{id: "approval-review-modal"})
         |> put_flash(:info, gettext("Decision recorded."))}

      {:error, error} ->
        {:noreply, assign(socket, :review_error, error_message(error))}
    end
  end

  def handle_event("control", %{"action" => action}, socket) when action in ["retry", "cancel"] do
    case Automations.control_run(socket.assigns.current_user, socket.assigns.resource.id, action) do
      {:ok, run} ->
        {:ok, run} = Automations.get_run(socket.assigns.current_user, run.id)

        {:noreply,
         socket
         |> assign(:resource, run)
         |> load_execution_events(%{"events_page" => socket.assigns.events_page})}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("toggle", %{"id" => id, "enabled" => enabled}, socket) do
    case Automations.set_trigger_enabled(socket.assigns.current_user, id, enabled == "true") do
      {:ok, _} -> {:noreply, load_list(socket, %{})}
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  defp load_execution_events(%{assigns: %{live_action: :execution}} = socket, params) do
    case Automations.execution_events(socket.assigns.current_user, socket.assigns.resource.id, %{
           "page" => params["events_page"] || 1
         }) do
      {:ok, {events, meta}} ->
        assign(socket, execution_events: events, events_meta: meta, events_page: meta.current_page, events_error: false)

      _ ->
        assign(socket, execution_events: [], events_meta: nil, events_error: true)
    end
  end

  defp load_execution_events(socket, _), do: socket

  defp load_detail(socket, %{"id" => id}) do
    result =
      case socket.assigns.live_action do
        :workflow -> Automations.get_workflow(socket.assigns.current_user, id)
        :execution -> Automations.get_run(socket.assigns.current_user, id)
      end

    case result do
      {:ok, resource} -> {:ok, assign_detail(socket, resource)}
      error -> error
    end
  end

  defp load_detail(socket, _), do: {:ok, assign_detail(socket, nil)}

  defp assign_detail(socket, %Workflow{} = workflow) do
    socket
    |> assign(:resource, workflow)
    |> assign(:definition, workflow_definition(workflow))
    |> assign(:page_title, workflow.name)
  end

  defp assign_detail(socket, resource), do: assign(socket, resource: resource, definition: nil)

  defp workflow_definition(%Workflow{published_revision: %Revision{} = revision}), do: revision
  defp workflow_definition(workflow), do: workflow

  defp analytics_enabled?(action), do: action in [:workflows, :workflow, :executions]

  defp assign_analytics_params(socket, params) do
    days = analytics_days(params["days"])
    until = analytics_end_date(params["end_date"], socket.assigns.analytics_end_date)
    preset = if params["end_date"] || days not in [7, 30, 90], do: "custom", else: "last-#{days}-days"

    metric =
      if params["metric"] in ["executions", "success_rate", "duration", "approvals"],
        do: params["metric"],
        else: "executions"

    socket
    |> assign(:analytics_days, days)
    |> assign(:analytics_end_date, until)
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_metric, metric)
    |> assign(
      :query_params,
      params
      |> Map.take(["page", "days", "metric", "end_date"] ++ Table.query_keys())
      |> Map.filter(fn {_, value} -> is_binary(value) end)
    )
  end

  defp assign_table_params(socket) do
    table = Table.state(socket.assigns.section, socket.assigns.query_params, socket.assigns.types)

    types =
      if socket.assigns.section == "behaviors", do: Table.types(socket.assigns.types, table), else: socket.assigns.types

    records_table =
      if socket.assigns.section == "behaviors",
        do: Table.state("configurations", socket.assigns.query_params, socket.assigns.types, "config_"),
        else: table

    available = Enum.uniq_by(table.available_filters ++ records_table.available_filters, & &1.id)
    active = Enum.uniq_by(table.active_filters ++ records_table.active_filters, & &1.id)

    socket
    |> assign(:table, table)
    |> assign(:records_table, records_table)
    |> assign(:available_filters, available)
    |> assign(:active_filters, active)
    |> assign(:visible_types, types)
  end

  defp analytics_days(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} when days in 1..90 -> days
      _ -> 30
    end
  end

  defp analytics_days(_), do: 30

  defp analytics_end_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> if date.year > 0 && Date.compare(date, Date.utc_today()) != :gt, do: date, else: fallback
      _ -> fallback
    end
  end

  defp analytics_end_date(_, fallback), do: fallback

  defp analytics_filters(socket) do
    filters = %{
      "days" => socket.assigns.analytics_days,
      "end_date" => Date.to_iso8601(socket.assigns.analytics_end_date)
    }

    id =
      if socket.assigns.live_action == :workflow,
        do: socket.assigns.resource.id

    if id, do: Map.put(filters, "workflow_id", id), else: filters
  end

  defp load_analytics(socket, force \\ false) do
    if analytics_enabled?(socket.assigns.live_action) && connected?(socket) do
      filters = analytics_filters(socket)

      if force || socket.assigns.analytics_key != filters do
        start_analytics(socket, filters)
      else
        socket
      end
    else
      socket
    end
  end

  defp start_analytics(socket, filters) do
    actor = socket.assigns.current_user

    result =
      if socket.assigns.analytics_key == filters, do: socket.assigns.execution_analytics, else: AsyncResult.loading()

    socket = if socket.assigns.analytics_key, do: cancel_async(socket, :execution_analytics), else: socket

    socket
    |> assign(:execution_analytics, result)
    |> assign(:analytics_key, filters)
    |> assign(:analytics_refreshed_at, System.monotonic_time(:second))
    |> assign_async(:execution_analytics, fn -> fetch_analytics(actor, filters) end)
  end

  defp fetch_analytics(actor, filters) do
    case Automations.execution_analytics(actor, filters) do
      {:ok, result} -> {:ok, %{execution_analytics: result}}
      {:error, error} -> {:error, error}
    end
  end

  defp refresh_analytics(socket) do
    if socket.assigns.analytics_refreshed_at &&
         System.monotonic_time(:second) - socket.assigns.analytics_refreshed_at >= 30 do
      load_analytics(socket, true)
    else
      socket
    end
  end

  defp analytics_patch(socket, changes) do
    if analytics_enabled?(socket.assigns.live_action) do
      params = socket.assigns.query_params |> Map.merge(changes) |> Map.reject(fn {_, value} -> is_nil(value) end)

      path =
        if socket.assigns.live_action == :workflow,
          do: "/automation/workflows/#{socket.assigns.resource.id}",
          else: "/automation/#{socket.assigns.section}"

      push_patch(socket, to: "#{path}?#{URI.encode_query(params)}", replace: true)
    else
      socket
    end
  end

  defp pagination_path(section, page, params) do
    "/automation/#{section}?#{URI.encode_query(Map.put(params, "page", page))}"
  end

  defp maybe_assign_form(%{assigns: %{editor_open: true}} = socket), do: socket
  defp maybe_assign_form(socket), do: assign_form(socket)

  defp list_key(socket, _params) do
    scope = if socket.assigns.live_action == :executions, do: analytics_filters(socket)
    table = Table.list_params(socket.assigns.records_table)
    {socket.assigns.live_action, to_string(socket.assigns.query_params["page"] || "1"), scope, table}
  end

  defp maybe_load_list(socket, _params) do
    params = socket.assigns.query_params
    if socket.assigns.list_key == list_key(socket, params), do: socket, else: load_list(socket, params)
  end

  defp load_list(%{assigns: %{live_action: action}} = socket, _params) when action in [:workflow, :execution],
    do: socket

  defp load_list(socket, params) do
    params = Map.merge(params, Table.list_params(socket.assigns.records_table))
    actor = socket.assigns.current_user

    result =
      case socket.assigns.section do
        "workflows" ->
          Automations.list_workflows(actor, params)

        "behaviors" ->
          Automations.list_behaviors(actor, params)

        "executions" ->
          Automations.list_runs(
            actor,
            params |> Map.merge(analytics_filters(socket))
          )

        "approvals" ->
          Automations.list_approvals(actor, params)

        "schedules" ->
          Automations.list_triggers(actor, "schedule", params)

        "webhooks" ->
          Automations.list_triggers(actor, "webhook", params)
      end

    case result do
      {:ok, {items, meta}} ->
        socket
        |> stream(:items, items, reset: true)
        |> assign(:records, Map.new(items, &{&1.id, &1}))
        |> assign(:list_key, list_key(socket, params))
        |> assign(:empty, items == [])
        |> assign(:page, meta.current_page)
        |> assign(:total_pages, max(meta.total_pages, 1))

      _ ->
        socket |> stream(:items, [], reset: true) |> assign(:records, %{}) |> assign(:empty, true)
    end
  end

  defp assign_form(socket) do
    defaults = %{
      "name" => "",
      "description" => "",
      "language" => "json",
      "source" => editable_source(%{language: "json", source: @example}),
      "type" => "core.value",
      "configuration" => "{}",
      "input" => "{}",
      "workflow_id" => "",
      "cron" => "0 9 * * 1"
    }

    values =
      case socket.assigns.resource do
        %Workflow{} = workflow ->
          definition = workflow_definition(workflow)

          Map.merge(defaults, %{
            "name" => workflow.name,
            "description" => workflow.description,
            "language" => definition.language,
            "source" => editable_source(definition)
          })

        _ ->
          defaults
      end

    socket |> assign(:form, to_form(values, as: :automation)) |> assign(:form_error, nil)
  end

  # Let Zag release its global pointer/scroll locks before navigation destroys the modal hook.
  defp navigate_after_close(socket, modal_id, path) do
    socket
    |> assign(:pending_navigation, %{modal_id: modal_id, path: path})
    |> push_event("close-modal", %{id: modal_id})
  end

  defp finish_navigation(socket, modal_id) do
    case socket.assigns.pending_navigation do
      %{modal_id: ^modal_id, path: path} ->
        socket |> assign(:pending_navigation, nil) |> push_navigate(to: path)

      _ ->
        socket
    end
  end

  defp form_failure(socket, attrs, error) do
    socket =
      socket
      |> assign(:form, to_form(attrs, as: :automation))
      |> assign(:form_error, error_message(error))

    if socket.assigns.editor_open, do: socket, else: put_flash(socket, :error, error_message(error))
  end

  defp save_workflow(actor, nil, attrs), do: Automations.save_workflow_version(actor, nil, attrs)

  defp save_workflow(actor, workflow, attrs) do
    attrs = Map.put(attrs, "input_schema", workflow_definition(workflow).input_schema)

    Automations.save_workflow_version(actor, workflow.id, attrs, expected_revision_id: workflow.published_revision_id)
  end

  defp editor_description("workflows", %Workflow{published_revision_id: id}) when not is_nil(id),
    do: gettext("Saving publishes a new version. Existing executions, schedules, and webhooks keep their version.")

  defp editor_description("workflows", _), do: gettext("Save a workflow to make its first version ready to run.")
  defp editor_description(section, _), do: description(section)

  defp save_label("workflows", %Workflow{published_revision_id: nil}), do: gettext("Save first version")
  defp save_label("workflows", %Workflow{}), do: gettext("Save new version")
  defp save_label(section, _), do: create_label(section)

  defp save_behavior(actor, attrs) do
    with {:ok, configuration} <- object(attrs["configuration"] || "{}") do
      Automations.create_behavior(actor, Map.put(attrs, "configuration", configuration))
    end
  end

  defp save_trigger(actor, section, attrs) do
    with {:ok, input} <- object(attrs["input"] || "{}") do
      attrs =
        attrs |> Map.put("input", input) |> Map.put("kind", if(section == "schedules", do: "schedule", else: "webhook"))

      Automations.create_trigger(actor, attrs["workflow_id"], attrs)
    end
  end

  defp object(source) do
    case JSON.decode(source) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _ -> {:error, "A JSON object is required."}
    end
  end

  defp editable_source(definition) do
    formatted = display_source(definition)
    if byte_size(formatted) <= 65_536, do: formatted, else: definition.source
  end

  defp display_source(%{language: "json", source: source}) do
    with {:ok, value} <- JSON.decode(source),
         true <- Contract.within_budget?(value, 65_536) do
      pretty(value)
    else
      _ -> source
    end
  end

  defp display_source(%{source: source}), do: source
  defp pretty(value), do: Jason.encode!(value, pretty: true)
  defp section(:workflow), do: "workflows"
  defp section(:execution), do: "executions"
  defp section(action), do: Atom.to_string(action)
  defp title("workflows"), do: gettext("Workflows")
  defp title("behaviors"), do: gettext("Behaviors")
  defp title("executions"), do: gettext("Executions")
  defp title("schedules"), do: gettext("Schedules")
  defp title("webhooks"), do: gettext("Webhooks")
  defp title("approvals"), do: gettext("Approvals")
  defp section_icon("workflows"), do: "schema"
  defp section_icon("behaviors"), do: "devices_code"
  defp section_icon("executions"), do: "history"
  defp section_icon("schedules"), do: "calendar_week"
  defp section_icon("webhooks"), do: "webhook"
  defp section_icon("approvals"), do: "circle_check"
  defp empty_columns("workflows"), do: [gettext("Name"), gettext("Status"), gettext("Language"), gettext("Created")]
  defp empty_columns("behaviors"), do: [gettext("Name"), gettext("Behavior type"), gettext("Created")]
  defp empty_columns("executions"), do: [gettext("Workflow"), gettext("Status"), gettext("Trigger"), gettext("Created")]

  defp empty_columns("schedules"),
    do: [
      gettext("Name"),
      gettext("Workflow"),
      gettext("Status"),
      gettext("Schedule"),
      gettext("Next run"),
      gettext("Actions")
    ]

  defp empty_columns("webhooks"),
    do: [gettext("Name"), gettext("Workflow"), gettext("Status"), gettext("Endpoint"), gettext("Actions")]

  defp empty_columns("approvals"),
    do: [gettext("Name"), gettext("Status"), gettext("Reviewer"), gettext("Created"), gettext("Actions")]

  defp creatable?(section), do: section in ["workflows", "behaviors", "schedules", "webhooks"]
  defp create_label("workflows"), do: gettext("Create workflow")
  defp create_label("behaviors"), do: gettext("Create behavior")
  defp create_label("schedules"), do: gettext("Create schedule")
  defp create_label("webhooks"), do: gettext("Create webhook")
  defp page_heading(section, nil), do: title(section)
  defp page_heading("workflows", workflow), do: workflow.name
  defp page_heading("executions", run), do: run.revision.workflow.name
  defp page_description(section, nil), do: description(section)
  defp page_description("workflows", workflow), do: workflow.description
  defp page_description("executions", run), do: gettext("Execution %{id}", id: String.slice(run.id, 0, 8))
  defp record_name("executions", run), do: run.revision.workflow.name
  defp record_name("approvals", approval), do: approval.step_id
  defp record_name(_, item), do: item.name
  defp record_description("executions", run), do: gettext("Execution %{id}", id: String.slice(run.id, 0, 8))
  defp record_description("approvals", approval), do: approval.run.revision.workflow.name
  defp record_description(_, item), do: Map.get(item, :description)
  defp row_navigate("workflows"), do: fn {_, item} -> ~p"/automation/workflows/#{item.id}" end
  defp row_navigate("executions"), do: fn {_, item} -> ~p"/automation/executions/#{item.id}" end
  defp row_navigate(_), do: nil
  defp language_label("json"), do: gettext("JSON")
  defp language_label("javascript"), do: gettext("JavaScript")
  defp status_label("queued"), do: gettext("Queued")
  defp status_label("running"), do: gettext("Running")
  defp status_label("waiting_approval"), do: gettext("Waiting for approval")
  defp status_label("succeeded"), do: gettext("Succeeded")
  defp status_label("failed"), do: gettext("Failed")
  defp status_label("cancelled"), do: gettext("Cancelled")
  defp status_label("pending"), do: gettext("Pending")
  defp status_label("approved"), do: gettext("Approved")
  defp status_label("rejected"), do: gettext("Rejected")
  defp status_label(value), do: Phoenix.Naming.humanize(value)
  defp status_kind(value) when value in ["succeeded", "approved"], do: "success"
  defp status_kind(value) when value in ["failed", "rejected"], do: "error"
  defp status_kind(value) when value in ["pending", "waiting_approval"], do: "attention"
  defp status_kind("running"), do: "in_progress"
  defp status_kind(_), do: "disabled"
  defp effect_label("read"), do: gettext("Read")
  defp effect_label("write"), do: gettext("Write")
  defp effect_label("compute"), do: gettext("Compute")
  defp trigger_label("manual"), do: gettext("Manual")
  defp trigger_label("schedule"), do: gettext("Schedule")
  defp trigger_label("webhook"), do: gettext("Webhook")
  defp description("workflows"), do: gettext("Create, version, and run repeatable processes.")
  defp description("behaviors"), do: gettext("Discover contracted types and save reusable configurations.")
  defp description("executions"), do: gettext("Inspect durable runs, step attempts, and results.")

  defp description("schedules"),
    do:
      gettext("Start pinned workflows on UTC schedules. Missed occurrences coalesce and overlapping runs are skipped.")

  defp description("webhooks"), do: gettext("Start pinned workflows from authenticated, deduplicated deliveries.")
  defp description("approvals"), do: gettext("Review the exact payload before a workflow continues.")
  defp error_message(%Ecto.Changeset{}), do: gettext("Check the required fields and their values.")
  defp error_message(error) when is_binary(error), do: error
  defp error_message(:forbidden), do: gettext("You do not have permission to perform this action.")

  defp error_message(:not_published),
    do: gettext("Save the first version before running the workflow or adding a trigger.")

  defp error_message(:workflow_changed),
    do: gettext("This workflow changed. Reload the page before saving a new version.")

  defp error_message(_), do: gettext("Could not complete the automation action.")
end
