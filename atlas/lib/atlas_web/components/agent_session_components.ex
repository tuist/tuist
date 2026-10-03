defmodule AtlasWeb.AgentSessionComponents do
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  attr :id, :string, required: true
  attr :sessions, :list, required: true
  attr :row_navigate, :any, required: true
  attr :empty_title, :string, default: nil
  attr :empty_subtitle, :string, default: nil

  def agent_sessions_table(assigns) do
    assigns =
      assigns
      |> assign(:empty_title, assigns.empty_title || gettext("No agent sessions yet"))
      |> assign(
        :empty_subtitle,
        assigns.empty_subtitle ||
          gettext(
            "Sessions show up here as agents run. Trigger an account overview, drop a screenshot note, or process an inbound email."
          )
      )

    ~H"""
    <.table id={@id} rows={@sessions} row_navigate={@row_navigate}>
      <:col :let={session} label={gettext("Agent")}>
        <.text_and_description_cell label={short_agent(session.agent)} description={session.agent} />
      </:col>
      <:col :let={session} label={gettext("Status")}>
        <.badge_cell label={status_label(session.status)} color={status_color(session.status)} />
      </:col>
      <:col :let={session} label={gettext("Account")}>
        <.text_cell label={account_label(loaded_account(session))} />
      </:col>
      <:col :let={session} label={gettext("Started")}>
        <.text_cell label={format_datetime(session.started_at)} />
      </:col>
      <:col :let={session} label={gettext("Duration")}>
        <.text_cell label={format_duration(session.duration_ms)} />
      </:col>
      <:empty_state>
        <.table_empty_state
          icon="message_circle"
          title={@empty_title}
          subtitle={@empty_subtitle}
        />
      </:empty_state>
    </.table>
    """
  end

  attr :id, :string, default: "agent-session"
  attr :session, :map, required: true
  attr :show_header, :boolean, default: true
  attr :back_label, :string, default: nil
  attr :back_path, :string, default: nil
  attr :back_icon, :boolean, default: true

  def agent_session_detail(assigns) do
    assigns =
      assigns
      |> assign(:activity, assigns.session.events |> Enum.sort_by(& &1.occurred_at, DateTime) |> build_activity())
      |> assign(:account, loaded_account(assigns.session))
      |> assign(:back_label, assigns.back_label || gettext("Back to sessions"))
      |> assign(:back_path, assigns.back_path || ~p"/admin/sessions")

    ~H"""
    <div id={@id} data-part="agent-session-detail">
      <div :if={@show_header} data-part="header">
        <div data-part="text">
          <h1 data-part="title">{short_agent(@session.agent)}</h1>
          <p data-part="description">{@session.agent}</p>
        </div>
        <div data-part="actions">
          <.button label={@back_label} navigate={@back_path} variant="secondary" size="small">
            <:icon_left :if={@back_icon}><.chevron_left /></:icon_left>
          </.button>
        </div>
      </div>

      <.card title={gettext("Run summary")} icon="info_circle" data-part="summary-card">
        <.card_section data-part="summary-section">
          <div data-part="metadata-grid">
            <div data-part="metadata-row">
              <.metadata_item title={gettext("Status")}>
                <.badge label={status_label(@session.status)} color={status_color(@session.status)} />
              </.metadata_item>
              <.metadata_item title={gettext("Account")}>
                <.link
                  :if={@account}
                  navigate={~p"/commercial/sales/accounts/#{@account.id}"}
                  data-part="account-link"
                >
                  {@account.name}
                </.link>
                <span :if={!@account}>-</span>
              </.metadata_item>
              <.metadata_item title={gettext("Started")}>
                {format_datetime(@session.started_at)}
              </.metadata_item>
              <.metadata_item title={gettext("Duration")}>
                {format_duration(@session.duration_ms)}
              </.metadata_item>
            </div>
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Prompt")} icon="message_circle" data-part="prompt-card">
        <.card_section data-part="prompt-section">
          <.prompt_view prompt={@session.prompt} />
        </.card_section>
      </.card>

      <.card :if={@session.result} title={gettext("Result")} icon="check" data-part="result-card">
        <.card_section data-part="result-section">
          {render_code_html(format_jsonb(@session.result), "json")}
        </.card_section>
      </.card>

      <.card :if={@session.error} title={gettext("Error")} icon="alert_circle" data-part="error-card">
        <.card_section data-part="error-section">
          {render_code_html(format_error_text(@session.error), "elixir")}
        </.card_section>
      </.card>

      <.card title={gettext("Activity")} icon="history" data-part="activity-card">
        <.card_section data-part="activity-section">
          <div :if={@activity == []} data-part="activity-empty" id={"#{@id}-activity-empty"}>
            {gettext("No telemetry events recorded for this session yet.")}
          </div>

          <ol :if={@activity != []} id={"#{@id}-activity"} data-part="activity-list">
            <li
              :for={item <- @activity}
              id={"#{@id}-activity-#{item.id}"}
              data-part="activity-row"
              data-kind={item.kind}
            >
              <.activity_entry item={item} />
            </li>
          </ol>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :prompt, :string, default: nil

  defp prompt_view(%{prompt: prompt} = assigns) do
    case parse_operation_prompt(prompt) do
      {operation, args} ->
        assigns = assign(assigns, operation: operation, formatted_args: format_jsonb(args))

        ~H"""
        <div data-part="prompt-operation">
          <span data-part="prompt-operation-label">{gettext("operation")}</span>
          <code data-part="prompt-operation-name">{@operation}</code>
        </div>
        {render_code_html(@formatted_args, "json")}
        """

      _ ->
        ~H"""
        <div data-part="prompt-markdown">{render_markdown_html(@prompt)}</div>
        """
    end
  end

  attr :item, :map, required: true

  defp activity_entry(%{item: %{kind: :turn}} = assigns) do
    ~H"""
    <header data-part="activity-row-header">
      <div data-part="activity-row-title">
        <.message_circle />
        <span data-part="title">{gettext("Turn %{n}", n: @item.turn)}</span>
      </div>
      <div data-part="activity-row-meta">
        <.badge
          :if={@item.finish_reason}
          label={@item.finish_reason}
          color="neutral"
          style="light-fill"
          size="small"
        />
        <.badge
          :if={@item.duration_ms}
          label={format_duration(@item.duration_ms)}
          color="neutral"
          style="light-fill"
          size="small"
        >
          <:icon><.history /></:icon>
        </.badge>
        <.badge
          :if={@item.usage_summary}
          label={@item.usage_summary}
          color="neutral"
          style="light-fill"
          size="small"
        />
      </div>
    </header>
    <div
      :if={
        @item.last_input || @item.assistant_text || @item.assistant_tool_calls != [] || @item.error
      }
      data-part="activity-row-body"
    >
      <div :if={@item.last_input} data-part="activity-line">
        <.badge
          label={role_label(@item.last_input.role)}
          color={role_color(@item.last_input.role)}
          style="light-fill"
          size="small"
        />
        <div data-part="activity-text">{render_markdown_html(@item.last_input.text)}</div>
      </div>
      <div :if={@item.assistant_text} data-part="activity-line">
        <.badge label={gettext("Assistant")} color="primary" style="light-fill" size="small" />
        <div data-part="activity-text">{render_markdown_html(@item.assistant_text)}</div>
      </div>
      <div :if={@item.assistant_tool_calls != []} data-part="activity-line">
        <span data-part="activity-line-label">{gettext("calls")}</span>
        <div data-part="activity-tool-call-list">
          <.badge
            :for={tc <- @item.assistant_tool_calls}
            label={tc}
            color="information"
            style="light-fill"
            size="small"
          />
        </div>
      </div>
      <div :if={@item.error} data-part="activity-line">
        <.badge label={gettext("Error")} color="destructive" style="light-fill" size="small" />
        {render_code_html(@item.error, "elixir")}
      </div>
    </div>
    """
  end

  defp activity_entry(%{item: %{kind: :tool_call}} = assigns) do
    ~H"""
    <header data-part="activity-row-header">
      <div data-part="activity-row-title">
        <.parentheses />
        <span data-part="activity-mono">{@item.tool}</span>
        <span data-part="subtitle">{gettext("tool call")}</span>
      </div>
      <div data-part="activity-row-meta">
        <.badge
          :if={@item.status}
          label={tool_status_label(@item.status)}
          color={tool_status_color(@item.status)}
          style="light-fill"
          size="small"
        />
        <.badge
          :if={@item.duration_ms}
          label={format_duration(@item.duration_ms)}
          color="neutral"
          style="light-fill"
          size="small"
        >
          <:icon><.history /></:icon>
        </.badge>
      </div>
    </header>
    <div :if={@item.args || @item.result} data-part="activity-row-body">
      <div :if={@item.args} data-part="activity-line">
        <span data-part="activity-line-label">{gettext("args")}</span>
        {render_code_html(format_jsonb(@item.args), "json")}
      </div>
      <div :if={@item.result} data-part="activity-line">
        <span data-part="activity-line-label">{gettext("result")}</span>
        {render_code_html(format_jsonb(@item.result), "json")}
      </div>
    </div>
    """
  end

  defp activity_entry(%{item: %{kind: :lifecycle}} = assigns) do
    ~H"""
    <header data-part="activity-row-header">
      <div data-part="activity-row-title">
        <span data-part="activity-dot" data-color={lifecycle_color(@item)}></span>
        <span data-part="title">{lifecycle_label(@item)}</span>
        <span data-part="subtitle">{lifecycle_phase_label(@item.phase)}</span>
      </div>
      <div data-part="activity-row-meta">
        <span data-part="activity-time">{format_time(@item.started_at)}</span>
        <.badge
          :if={@item.duration_ms}
          label={format_duration(@item.duration_ms)}
          color="neutral"
          style="light-fill"
          size="small"
        >
          <:icon><.history /></:icon>
        </.badge>
      </div>
    </header>
    """
  end

  defp lifecycle_phase_label("start"), do: gettext("started")
  defp lifecycle_phase_label("stop"), do: gettext("finished")
  defp lifecycle_phase_label("exception"), do: gettext("raised")
  defp lifecycle_phase_label("resolve"), do: gettext("resolved")
  defp lifecycle_phase_label("access"), do: gettext("accessed")
  defp lifecycle_phase_label(other) when is_binary(other), do: other
  defp lifecycle_phase_label(_), do: nil

  defp loaded_account(%{account: %Ecto.Association.NotLoaded{}}), do: nil
  defp loaded_account(%{account: account}), do: account
  defp loaded_account(_), do: nil

  defp account_label(%{name: name}) when is_binary(name), do: name
  defp account_label(_), do: "-"

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp metadata_item(assigns) do
    ~H"""
    <div data-part="metadata">
      <div data-part="metadata-title">{@title}</div>
      <div data-part="metadata-value">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp status_label("succeeded"), do: gettext("Succeeded")
  defp status_label("failed"), do: gettext("Failed")
  defp status_label("running"), do: gettext("Running")
  defp status_label(other), do: other

  defp status_color("succeeded"), do: "success"
  defp status_color("failed"), do: "destructive"
  defp status_color("running"), do: "information"
  defp status_color(_), do: "neutral"

  defp role_label("user"), do: gettext("User")
  defp role_label("tool_result"), do: gettext("Tool result")
  defp role_label("system"), do: gettext("System")
  defp role_label(other) when is_binary(other), do: other

  defp role_color("user"), do: "neutral"
  defp role_color("tool_result"), do: "information"
  defp role_color("system"), do: "secondary"
  defp role_color(_), do: "neutral"

  defp short_agent(agent) when is_binary(agent), do: agent |> String.split(".") |> List.last()
  defp short_agent(_), do: "-"

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M:%S")
  defp format_datetime(_), do: "-"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S.%f")
  defp format_time(_), do: "-"

  defp format_duration(nil), do: "-"
  defp format_duration(ms) when ms < 1_000, do: "#{ms} ms"
  defp format_duration(ms), do: :io_lib.format("~.2f s", [ms / 1_000]) |> IO.iodata_to_binary()

  defp format_jsonb(value), do: pretty_json(value, 0)

  defp render_markdown_html(text) when is_binary(text) and text != "" do
    text
    |> prepare_markdown()
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> raw()
  end

  defp render_markdown_html(_), do: nil

  defp render_code_html(code, lang) when is_binary(code) and code != "" and is_binary(lang) do
    ("```" <> lang <> "\n" <> code <> "\n```")
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> raw()
  end

  defp render_code_html(_, _), do: nil

  # Pretty-print embedded ```json``` blocks so single-line JSON payloads
  # (common in agent prompts) render as multi-line, syntax-highlighted code.
  defp prepare_markdown(text) do
    Regex.replace(~r/```json\s*\n(.*?)\n\s*```/s, text, fn full, json ->
      case Jason.decode(json) do
        {:ok, decoded} -> "```json\n" <> Jason.encode!(decoded, pretty: true) <> "\n```"
        _ -> full
      end
    end)
  end

  defp parse_operation_prompt("operation:" <> rest) do
    case String.split(rest, " ", parts: 2) do
      [operation, payload] ->
        case JSON.decode(payload) do
          {:ok, args} -> {operation, args}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_operation_prompt(_), do: nil

  defp format_error_text(error) when is_binary(error) do
    error
    |> Code.format_string!(line_length: 80)
    |> IO.iodata_to_binary()
  rescue
    _ -> error
  end

  defp format_error_text(error), do: inspect(error, pretty: true, width: 80)

  defp pretty_json(value, indent) when is_map(value) and not is_struct(value), do: pretty_map(value, indent)
  defp pretty_json([], _indent), do: "[]"
  defp pretty_json(value, indent) when is_list(value), do: pretty_list(value, indent)
  defp pretty_json(true, _indent), do: "true"
  defp pretty_json(false, _indent), do: "false"
  defp pretty_json(nil, _indent), do: "null"
  defp pretty_json(value, _indent) when is_binary(value), do: ~s|"#{escape_json_string(value)}"|
  defp pretty_json(value, _indent) when is_integer(value) or is_float(value), do: to_string(value)
  defp pretty_json(other, _indent), do: ~s|"#{escape_json_string(inspect(other))}"|

  defp pretty_map(map, _indent) when map_size(map) == 0, do: "{}"

  defp pretty_map(map, indent) do
    pad = String.duplicate("  ", indent)
    inner_pad = String.duplicate("  ", indent + 1)

    entries =
      map
      |> Enum.sort_by(fn {key, _} -> to_string(key) end)
      |> Enum.map_join(",\n", fn {key, value} ->
        ~s|#{inner_pad}"#{key}": #{pretty_json(value, indent + 1)}|
      end)

    "{\n#{entries}\n#{pad}}"
  end

  defp pretty_list(list, indent) do
    pad = String.duplicate("  ", indent)
    inner_pad = String.duplicate("  ", indent + 1)

    entries =
      Enum.map_join(list, ",\n", fn value ->
        "#{inner_pad}#{pretty_json(value, indent + 1)}"
      end)

    "[\n#{entries}\n#{pad}]"
  end

  defp escape_json_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  # Walks events in chronological order, pairs start/stop/exception emissions
  # by their natural correlation key, and folds them into typed activity
  # entries (LLM turns, tool calls, lifecycle markers).
  defp build_activity(events) do
    {items, pending} = Enum.reduce(events, {[], %{}}, &fold_event/2)

    orphans = Enum.map(Map.values(pending), &activity_item([&1]))

    (items ++ orphans)
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  defp fold_event(event, {items, pending}) do
    case event.phase do
      "start" ->
        {items, Map.put(pending, pair_key(event), event)}

      phase when phase in ["stop", "exception"] ->
        case Map.pop(pending, pair_key(event)) do
          {nil, pending} -> {[activity_item([event]) | items], pending}
          {start, pending} -> {[activity_item([start, event]) | items], pending}
        end

      _ ->
        {[activity_item([event]) | items], pending}
    end
  end

  defp pair_key(%{type: "tool_call", metadata: %{"tool_call_id" => id}}) when is_binary(id), do: {:tool_call, id}
  defp pair_key(%{type: "llm_turn", metadata: %{"turn" => turn}}), do: {:llm_turn, turn}
  defp pair_key(%{type: type, name: name}) when is_binary(name), do: {type, name}
  defp pair_key(%{type: type, id: id}), do: {type, id}

  defp activity_item(events) do
    sorted = Enum.sort_by(events, & &1.occurred_at, DateTime)
    first = List.first(sorted)
    last = List.last(sorted)
    started_at = first.occurred_at
    duration_ms = pair_duration(sorted)

    base = %{
      id: first.id,
      type: first.type,
      name: first.name,
      started_at: started_at,
      duration_ms: duration_ms
    }

    case first.type do
      "llm_turn" -> turn_item(base, sorted)
      "tool_call" -> tool_call_item(base, sorted)
      _ -> lifecycle_item(base, sorted, last)
    end
  end

  defp pair_duration([_single]), do: nil

  defp pair_duration(events) do
    case Enum.find(events, &(&1.phase in ["stop", "exception"])) do
      nil -> nil
      event -> event.duration_ms
    end
  end

  defp turn_item(base, events) do
    stop = Enum.find(events, &(&1.phase == "stop"))
    exception = Enum.find(events, &(&1.phase == "exception"))
    metadata = (stop || List.first(events) || exception).metadata
    assistant = stop && stop.metadata["assistant_message"]

    Map.merge(base, %{
      kind: :turn,
      turn: metadata["turn"],
      finish_reason: metadata["finish_reason"],
      usage_summary: usage_summary(metadata["usage"]),
      last_input: last_input(metadata["messages"] || []),
      assistant_text: assistant && message_text(assistant),
      assistant_tool_calls: assistant_tool_calls(assistant),
      error: exception && exception_message(exception)
    })
  end

  defp tool_call_item(base, events) do
    start_event = Enum.find(events, &(&1.phase == "start"))
    stop_event = Enum.find(events, &(&1.phase == "stop"))
    metadata = (stop_event || start_event).metadata
    args = (start_event && start_event.metadata["args"]) || metadata["args"]

    Map.merge(base, %{
      kind: :tool_call,
      tool: metadata["tool"] || base.name,
      args: args,
      result: stop_event && stop_event.metadata["result"],
      status: tool_status(metadata)
    })
  end

  defp lifecycle_item(base, _events, last) do
    Map.merge(base, %{
      kind: :lifecycle,
      phase: last.phase,
      status: last.metadata["status"]
    })
  end

  defp tool_status(%{"status" => "ok"}), do: :ok
  defp tool_status(%{"status" => :ok}), do: :ok
  defp tool_status(%{"status" => "error"}), do: :error
  defp tool_status(%{"status" => :error}), do: :error
  defp tool_status(_), do: nil

  defp tool_status_label(:ok), do: gettext("OK")
  defp tool_status_label(:error), do: gettext("Error")
  defp tool_status_label(_), do: gettext("Pending")

  defp tool_status_color(:ok), do: "success"
  defp tool_status_color(:error), do: "destructive"
  defp tool_status_color(_), do: "neutral"

  defp lifecycle_label(%{type: type, name: name}) when is_binary(name) and name != "" do
    "#{lifecycle_type_label(type)}: #{name}"
  end

  defp lifecycle_label(%{type: type}), do: lifecycle_type_label(type)

  defp lifecycle_type_label("run"), do: gettext("Run")
  defp lifecycle_type_label("agent"), do: gettext("Agent")
  defp lifecycle_type_label("operation"), do: gettext("Operation")
  defp lifecycle_type_label("subagent"), do: gettext("Subagent")
  defp lifecycle_type_label("compact"), do: gettext("Compact")
  defp lifecycle_type_label("secrets"), do: gettext("Secrets")
  defp lifecycle_type_label(other), do: other

  defp lifecycle_color(%{phase: "exception"}), do: "destructive"
  defp lifecycle_color(%{status: "error"}), do: "destructive"
  defp lifecycle_color(%{status: "ok"}), do: "success"
  defp lifecycle_color(_), do: "neutral"

  defp exception_message(event) do
    case event.metadata["reason"] do
      reason when is_binary(reason) -> format_error_text(reason)
      nil -> format_jsonb(event.metadata)
      other -> format_jsonb(other)
    end
  end

  defp last_input([]), do: nil

  defp last_input(messages) do
    messages
    |> List.last()
    |> case do
      %{"role" => role} = msg when role in ["user", "tool_result"] ->
        %{role: role, text: message_text(msg) || "-"}

      _ ->
        nil
    end
  end

  defp message_text(%{"content" => content}), do: content_text(content)
  defp message_text(_), do: nil

  defp content_text(text) when is_binary(text), do: text

  defp content_text(parts) when is_list(parts) do
    parts
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} when is_binary(text) -> [text]
      _ -> []
    end)
    |> Enum.join("\n")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp content_text(_), do: nil

  defp assistant_tool_calls(nil), do: []

  defp assistant_tool_calls(%{"content" => parts}) when is_list(parts) do
    Enum.flat_map(parts, fn
      %{"type" => "tool_call", "name" => name} -> [name]
      %{"type" => "tool_use", "name" => name} -> [name]
      _ -> []
    end)
  end

  defp assistant_tool_calls(_), do: []

  defp usage_summary(%{"input_tokens" => input, "output_tokens" => output}) do
    "↑ #{input} / ↓ #{output} tokens"
  end

  defp usage_summary(_), do: nil
end
