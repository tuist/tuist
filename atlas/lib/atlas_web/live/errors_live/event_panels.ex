defmodule AtlasWeb.ErrorsLive.EventPanels do
  @moduledoc """
  Shared function components for the tags, contexts, request,
  breadcrumbs, additional-data, modules, and SDK cards on the error
  issue and event detail pages. Kept in one module so both pages
  render identically.
  """

  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  attr :issue, :map, required: true
  attr :payload, :map, required: true

  def tags_card(assigns) do
    ~H"""
    <.card
      :if={tag_pairs(@issue, @payload) != []}
      title={gettext("Tags")}
      icon="alert_hexagon"
    >
      <.card_section>
        <div data-part="context-metadata-grid" data-columns="2">
          <div :for={{key, value} <- tag_pairs(@issue, @payload)} data-part="context-metadata">
            <div data-part="title">{key}</div>
            <span data-part="label">{value}</span>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :payload, :map, required: true

  def contexts_card(assigns) do
    ~H"""
    <.card
      :if={contexts(@payload) != []}
      title={gettext("Contexts")}
      icon="stack_2"
    >
      <.card_section>
        <div data-part="contexts-grid">
          <div :for={{name, data} <- contexts(@payload)} data-part="context-card">
            <div data-part="context-header">
              <div data-part="context-icon" data-color={context_color(name)}>
                <.icon name={context_icon(name)} />
              </div>
              <span data-part="context-title">{format_context_name(name)}</span>
            </div>
            <div data-part="context-metadata-grid">
              <div :for={{k, v} <- flatten_context(data)} data-part="context-metadata">
                <div data-part="title">{k}</div>
                <span data-part="label">{format_context_value(v)}</span>
              </div>
            </div>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :payload, :map, required: true

  def request_card(assigns) do
    assigns = assign(assigns, :req, request_data(assigns.payload))

    ~H"""
    <.card
      :if={@req}
      title={gettext("Request")}
      icon="server"
    >
      <.card_section>
        <div data-part="request">
          <div :if={@req["method"] || @req["url"]} data-part="request-line">
            <.badge
              label={String.upcase(@req["method"] || "GET")}
              color={http_method_color(@req["method"])}
              style="light-fill"
              size="small"
            />
            <code>{@req["url"]}</code>
          </div>

          <div :if={@req["query_string"] || @req["data"]} data-part="context-metadata-grid">
            <div :if={@req["query_string"]} data-part="context-metadata">
              <div data-part="title">{gettext("Query string")}</div>
              <span data-part="label"><code>{@req["query_string"]}</code></span>
            </div>
            <div :if={@req["data"]} data-part="context-metadata">
              <div data-part="title">{gettext("Body")}</div>
              <span data-part="label">
                <pre data-part="request-body">{format_context_value(@req["data"])}</pre>
              </span>
            </div>
          </div>

          <div
            :if={is_map(@req["headers"]) and map_size(@req["headers"]) > 0}
            data-part="request-headers"
          >
            <div data-part="request-headers-title">
              {gettext("Headers")}
            </div>
            <div data-part="context-metadata-grid" data-columns="2">
              <div
                :for={{k, v} <- Enum.sort(@req["headers"])}
                data-part="context-metadata"
              >
                <div data-part="title">{k}</div>
                <span data-part="label">{v}</span>
              </div>
            </div>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :payload, :map, required: true

  def breadcrumbs_card(assigns) do
    ~H"""
    <.card
      :if={event_breadcrumbs(@payload) != []}
      title={gettext("Breadcrumbs")}
      icon="list_tree"
    >
      <.card_section>
        <div data-part="timeline">
          <div
            :for={crumb <- event_breadcrumbs(@payload)}
            data-part="timeline-item"
            data-level={crumb["level"] || "info"}
          >
            <div data-part="timeline-icon" data-color={crumb_color(crumb["level"])}>
              <.icon name={crumb_icon(crumb["category"] || crumb["type"])} />
            </div>
            <div data-part="timeline-content">
              <div data-part="timeline-header">
                <.badge
                  label={crumb["category"] || crumb["type"] || "log"}
                  color={crumb_badge_color(crumb["level"])}
                  style="light-fill"
                  size="small"
                />
                <span :if={crumb["message"]} data-part="timeline-title">
                  {crumb["message"]}
                </span>
              </div>
              <pre
                :if={is_map(crumb["data"]) and map_size(crumb["data"]) > 0}
                data-part="timeline-data"
              ><code>{format_context_value(crumb["data"])}</code></pre>
            </div>
            <span data-part="timeline-time" title={format_datetime(crumb["timestamp"])}>
              {crumb_relative_time(crumb["timestamp"])}
            </span>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :payload, :map, required: true

  def additional_data_card(assigns) do
    ~H"""
    <.card
      :if={extra_pairs(@payload) != []}
      title={gettext("Additional data")}
      icon="database"
    >
      <.card_section>
        <div data-part="context-metadata-grid">
          <div :for={{k, v} <- extra_pairs(@payload)} data-part="context-metadata">
            <div data-part="title">{k}</div>
            <span data-part="label">{format_context_value(v)}</span>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :payload, :map, required: true

  def modules_card(assigns) do
    ~H"""
    <.card
      :if={module_pairs(@payload) != []}
      title={gettext("Modules")}
      icon="package"
    >
      <.card_section>
        <div data-part="context-metadata-grid" data-columns="2">
          <div :for={{name, version} <- module_pairs(@payload)} data-part="context-metadata">
            <div data-part="title">{name}</div>
            <span data-part="label">{version}</span>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr :payload, :map, required: true

  def sdk_card(assigns) do
    assigns = assign(assigns, :sdk, sdk_info(assigns.payload))

    ~H"""
    <.card
      :if={@sdk}
      title={gettext("SDK")}
      icon="devices_code"
    >
      <.card_section>
        <div data-part="context-metadata-grid">
          <div :if={@sdk["name"]} data-part="context-metadata">
            <div data-part="title">{gettext("Name")}</div>
            <span data-part="label">{@sdk["name"]}</span>
          </div>
          <div :if={@sdk["version"]} data-part="context-metadata">
            <div data-part="title">{gettext("Version")}</div>
            <span data-part="label">{@sdk["version"]}</span>
          </div>
          <div
            :if={is_list(@sdk["integrations"]) and @sdk["integrations"] != []}
            data-part="context-metadata"
          >
            <div data-part="title">{gettext("Integrations")}</div>
            <span data-part="label" data-part-inner="badge-row">
              <.badge
                :for={integration <- @sdk["integrations"]}
                label={integration}
                color="focus"
                style="light-fill"
                size="small"
              />
            </span>
          </div>
          <div
            :if={is_list(@sdk["packages"]) and @sdk["packages"] != []}
            data-part="context-metadata"
          >
            <div data-part="title">{gettext("Packages")}</div>
            <span data-part="label" data-part-inner="badge-row">
              <.badge
                :for={pkg <- @sdk["packages"]}
                label={"#{pkg["name"]}@#{pkg["version"]}"}
                color="neutral"
                style="light-fill"
                size="small"
              />
            </span>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  ## Payload readers

  def tag_pairs(issue, payload) do
    payload_tags = as_map(payload["tags"])

    base = [
      {"environment", get(payload, "environment", "")},
      {"level", to_string(issue.level)},
      {"platform", get(payload, "platform", "")},
      {"release", get(payload, "release", "")},
      {"dist", get(payload, "dist", "")},
      {"server_name", get(payload, "server_name", "")},
      {"transaction", get(payload, "transaction", "")},
      {"logger", get(payload, "logger", "")}
    ]

    (base ++ Enum.to_list(payload_tags))
    |> Enum.reject(fn {_, v} -> v == "" or is_nil(v) end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.sort_by(&elem(&1, 0))
  end

  @known_contexts ~w(user os runtime device browser app culture trace cloud_resource state response replay)

  def contexts(payload) do
    map = as_map(payload["contexts"])

    user =
      case as_map(payload["user"]) do
        empty when map_size(empty) == 0 -> nil
        u -> u
      end

    map = if user, do: Map.put_new(map, "user", user), else: map

    map
    |> Enum.filter(fn {_k, v} -> is_map(v) and map_size(v) > 0 end)
    |> Enum.sort_by(fn {k, _} -> context_order(k) end)
  end

  defp context_order(name) do
    case Enum.find_index(@known_contexts, &(&1 == name)) do
      nil -> length(@known_contexts) + :erlang.phash2(name, 1000)
      idx -> idx
    end
  end

  @context_acronyms MapSet.new(~w(os sdk gpu cpu url http api ssl tls ip id))

  def format_context_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", fn word ->
      if MapSet.member?(@context_acronyms, String.downcase(word)) do
        String.upcase(word)
      else
        String.capitalize(word)
      end
    end)
  end

  def flatten_context(map) when is_map(map) do
    map
    |> Enum.reject(fn {k, _} -> k == "type" end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  def flatten_context(_), do: []

  def format_context_value(nil), do: "-"
  def format_context_value(v) when is_binary(v), do: v
  def format_context_value(v) when is_number(v) or is_boolean(v), do: to_string(v)

  def format_context_value(map) when is_map(map) do
    if Enum.all?(map, fn {_, v} -> is_binary(v) or is_number(v) or is_boolean(v) end) do
      Enum.map_join(map, ", ", fn {k, v} -> "#{k}: #{v}" end)
    else
      Jason.encode!(map, pretty: true)
    end
  end

  def format_context_value(v), do: Jason.encode!(v, pretty: true)

  def request_data(payload) do
    case as_map(payload["request"]) do
      empty when map_size(empty) == 0 -> nil
      m -> m
    end
  end

  def event_breadcrumbs(payload) do
    case payload["breadcrumbs"] do
      %{"values" => values} when is_list(values) -> values
      values when is_list(values) -> values
      _ -> []
    end
  end

  def extra_pairs(payload) do
    payload["extra"]
    |> as_map()
    |> Enum.sort_by(&elem(&1, 0))
  end

  def module_pairs(payload) do
    payload["modules"]
    |> as_map()
    |> Enum.sort_by(&elem(&1, 0))
  end

  def sdk_info(payload) do
    case as_map(payload["sdk"]) do
      empty when map_size(empty) == 0 -> nil
      m -> m
    end
  end

  ## Formatters shared with LiveView helpers

  def format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  def format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  def format_datetime(bin) when is_binary(bin), do: bin
  def format_datetime(_), do: "-"

  def relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> gettext("%{n}s ago", n: diff)
      diff < 3600 -> gettext("%{n}m ago", n: div(diff, 60))
      diff < 86_400 -> gettext("%{n}h ago", n: div(diff, 3600))
      diff < 30 * 86_400 -> gettext("%{n}d ago", n: div(diff, 86_400))
      diff < 365 * 86_400 -> gettext("%{n}mo ago", n: div(diff, 30 * 86_400))
      true -> gettext("%{n}y ago", n: div(diff, 365 * 86_400))
    end
  end

  def relative_time(_), do: "-"

  def to_datetime(%DateTime{} = dt), do: dt
  def to_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  def to_datetime(bin) when is_binary(bin) do
    case DateTime.from_iso8601(bin) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  def to_datetime(_), do: nil

  ## Context icon + color

  def context_icon("user"), do: "user"
  def context_icon("os"), do: "server"
  def context_icon("runtime"), do: "devices_code"
  def context_icon("device"), do: "device_desktop"
  def context_icon("browser"), do: "devices_browser"
  def context_icon("app"), do: "apps"
  def context_icon("culture"), do: "language"
  def context_icon("trace"), do: "link_icon"
  def context_icon("cloud_resource"), do: "server"
  def context_icon("state"), do: "database"
  def context_icon("response"), do: "arrow_left"
  def context_icon("replay"), do: "player_play"
  def context_icon(_), do: "info_circle"

  def context_color("user"), do: "information"
  def context_color("os"), do: "neutral"
  def context_color("runtime"), do: "focus"
  def context_color("device"), do: "neutral"
  def context_color("browser"), do: "information"
  def context_color("app"), do: "success"
  def context_color("trace"), do: "focus"
  def context_color(_), do: "neutral"

  ## Breadcrumb icon + color

  def crumb_icon("http"), do: "server"
  def crumb_icon("http.request"), do: "server"
  def crumb_icon("http.response"), do: "server"
  def crumb_icon("db.query"), do: "database"
  def crumb_icon("db"), do: "database"
  def crumb_icon("app.lifecycle"), do: "apps"
  def crumb_icon("navigation"), do: "link_icon"
  def crumb_icon("ui.click"), do: "apps"
  def crumb_icon("ui." <> _), do: "apps"
  def crumb_icon("console"), do: "devices_code"
  def crumb_icon("query"), do: "database"
  def crumb_icon(_), do: "info_circle"

  def crumb_color("error"), do: "destructive"
  def crumb_color("fatal"), do: "destructive"
  def crumb_color("warning"), do: "warning"
  def crumb_color("info"), do: "information"
  def crumb_color("debug"), do: "neutral"
  def crumb_color(_), do: "neutral"

  def crumb_badge_color("error"), do: "destructive"
  def crumb_badge_color("fatal"), do: "destructive"
  def crumb_badge_color("warning"), do: "warning"
  def crumb_badge_color("info"), do: "information"
  def crumb_badge_color(_), do: "neutral"

  def crumb_relative_time(nil), do: ""
  def crumb_relative_time(""), do: ""

  def crumb_relative_time(ts) do
    case to_datetime(ts) do
      %DateTime{} = dt -> relative_time(dt)
      _ -> to_string(ts)
    end
  end

  ## HTTP method → badge color

  def http_method_color("GET"), do: "information"
  def http_method_color("POST"), do: "success"
  def http_method_color("PUT"), do: "warning"
  def http_method_color("PATCH"), do: "warning"
  def http_method_color("DELETE"), do: "destructive"

  def http_method_color(method) when is_binary(method), do: http_method_color(String.upcase(method))

  def http_method_color(_), do: "neutral"

  ## Small utilities

  defp as_map(m) when is_map(m), do: m
  defp as_map(_), do: %{}

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default) || default
  defp get(_, _, default), do: default
end
