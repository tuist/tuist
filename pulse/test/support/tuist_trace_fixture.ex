defmodule Pulse.Test.TuistTraceFixture do
  @moduledoc false
  # OTLP/JSON spans shaped like the tuist server's, kura's and the registry's
  # real exports: Phoenix/Ecto/Oban spans with `selected_account_handle`,
  # `error.type` and exceptions recorded as OTel span events named
  # `exception` (`exception.type/message/stacktrace`). Every trace documents
  # which dashboard queries must and must not select it.

  @doc "Dashboard queries as Grafana sends them, variables expanded."
  def queries do
    %{
      account: ~s[{ span.selected_account_handle = "tuist" }],
      account_errors: ~s[{ span.selected_account_handle = "tuist" } >> { span.error.type != "" }],
      errors_by_type: ~s[{ event.exception.type != "" } | select(event.exception.type)],
      recent_errors: ~s[{ status = error } | select(event.exception.type, event.exception.message)],
      stacktraces: ~s[{ event.exception.stacktrace != "" } | select(event.exception.type, event.exception.stacktrace)],
      kura_cache:
        ~s[{ resource.service.namespace = "kura" && resource.service.name =~ "kura-(acme)-.*" && span.http.route =~ "/api/cache.*|/api/metro/cache.*|/v1/cache.*" } with (most_recent=true)],
      registry:
        ~s[{ resource.service.namespace = "tuist" && resource.service.name = "tuist-registry" && resource.deployment.environment =~ "production" } with (most_recent=true)],
      kura: ~s[{ resource.service.namespace = "kura" }]
    }
  end

  @doc "Error Monitoring metrics panels: query => spans it counts."
  def rates do
    %{
      ~s[{ status = error } | rate()] => 5,
      ~s[{ event.exception.stacktrace != "" } | rate()] => 5,
      ~s[{ event.exception.type = "Postgrex.Error" } | rate()] => 2,
      ~s[{ event.exception.type = "Bandit.HTTPError" } | rate()] => 1,
      ~s[{ event.exception.type = "Elixir.TuistWeb.Errors.NotFoundError" } | rate()] => 1,
      ~s[{ event.exception.type = "Oban.PerformError" } | rate()] => 1,
      ~s[{ event.exception.type =~ ".*DBConnection.ConnectionError" } | rate()] => 1
    }
  end

  def id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
  def span_id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(16, "0")

  @doc "Trace ID => the span IDs each search query returns, in Tempo semantics."
  def expected do
    %{
      account: %{id(1) => [span_id(11)], id(2) => [span_id(21)], id(4) => [span_id(41)]},
      # T4's root carries both attributes itself: `>>` needs a strict descendant.
      account_errors: %{id(1) => [span_id(12), span_id(13)]},
      errors_by_type: %{
        id(1) => [span_id(13)],
        id(5) => [span_id(51), span_id(52)],
        id(6) => [span_id(61), span_id(62)]
      },
      recent_errors: %{
        id(1) => [span_id(13)],
        id(3) => [span_id(32)],
        id(5) => [span_id(51)],
        id(6) => [span_id(61), span_id(63)]
      },
      stacktraces: %{
        id(1) => [span_id(13)],
        id(5) => [span_id(51), span_id(52)],
        id(6) => [span_id(61), span_id(62)]
      },
      kura_cache: %{id(7) => [span_id(71)]},
      registry: %{id(9) => [span_id(91)]},
      kura: %{id(7) => [span_id(71), span_id(72)], id(8) => [span_id(81), span_id(82)]}
    }
  end

  @doc "OTLP/JSON export requests (one per service), spans starting at `start_ns`."
  def requests(start_ns) do
    server = [ns: "tuist", name: "tuist-server", env: "production"]

    [
      {server,
       [
         # T1: account request whose Ecto child and grandchild failed.
         span(1, 11, nil, start_ns, "GET /api/projects", 2, 0, handle: "tuist", route: "/api/projects"),
         span(1, 12, 11, start_ns + 1, "tuist.repo.query", 3, 0, error_type: "Elixir.DBConnection.ConnectionError"),
         span(1, 13, 12, start_ns + 2, "Postgrex query", 3, 2,
           error_type: "Elixir.DBConnection.ConnectionError",
           exceptions: [exception("Elixir.DBConnection.ConnectionError", "connection not available")]
         ),
         # T2: healthy account request.
         span(2, 21, nil, start_ns + 10, "GET /api/runs", 2, 0, handle: "tuist", route: "/api/runs"),
         span(2, 22, 21, start_ns + 11, "tuist.repo.query", 3, 0, []),
         # T3: another account's error; failing span without exception event.
         span(3, 31, nil, start_ns + 20, "GET /api/cache", 2, 0, handle: "other"),
         span(3, 32, 31, start_ns + 21, "tuist.repo.query", 3, 2, error_type: "timeout"),
         # T4: the account span itself has error.type, no erroring descendant.
         span(4, 41, nil, start_ns + 30, "GET /api/account", 2, 0,
           handle: "tuist",
           error_type: "Bandit.TransportError"
         ),
         span(4, 42, 41, start_ns + 31, "render", 1, 0, []),
         # T5: Oban job failure; a sibling span carries two exception events.
         span(5, 51, nil, start_ns + 40, "Tuist.Workers.Build process", 5, 2,
           exceptions: [exception("Oban.PerformError", "job failed")]
         ),
         span(5, 52, 51, start_ns + 41, "tuist.repo.query", 3, 0,
           exceptions: [exception("Postgrex.Error", "deadlock detected"), exception("Bandit.HTTPError", "closed")]
         ),
         # T6: 404 recorded as an exception without error status; status
         # error with an empty-typed exception and stacktrace-less event.
         span(6, 61, nil, start_ns + 50, "GET /missing", 2, 2,
           exceptions: [exception("Postgrex.Error", "relation does not exist")]
         ),
         span(6, 62, 61, start_ns + 51, "render 404", 1, 0,
           exceptions: [exception("Elixir.TuistWeb.Errors.NotFoundError", "not found")]
         ),
         span(6, 63, 61, start_ns + 52, "flush", 1, 2, exceptions: [%{"exception.message" => "no type"}])
       ]},
      {[ns: "kura", name: "kura-acme-eu-1"],
       [
         span(7, 71, nil, start_ns + 60, "GET /api/cache/cas/:id", 2, 0, route: "/api/cache/cas/:id"),
         span(7, 72, 71, start_ns + 61, "disk read", 1, 0, [])
       ]},
      {[ns: "kura", name: "kura-other-eu-1"],
       [
         # Same route, other tenant: excluded by the service-name regex.
         span(8, 81, nil, start_ns + 70, "GET /api/cache/cas/:id", 2, 0, route: "/api/cache/cas/:id"),
         span(8, 82, 81, start_ns + 71, "GET /up", 2, 0, route: "/up")
       ]},
      {[ns: "tuist", name: "tuist-registry", env: "production"],
       [span(9, 91, nil, start_ns + 80, "GET /api/registry", 2, 0, route: "/api/registry")]},
      {[ns: "tuist", name: "tuist-registry", env: "staging"],
       [span(10, 101, nil, start_ns + 90, "GET /api/registry", 2, 0, route: "/api/registry")]}
    ]
    |> Enum.map(fn {resource, spans} -> request(resource, spans) end)
  end

  defp exception(type, message) do
    %{"exception.type" => type, "exception.message" => message, "exception.stacktrace" => "lib/tuist.ex:1: #{type}"}
  end

  defp request(resource, spans) do
    attributes =
      [
        {"service.namespace", resource[:ns]},
        {"service.name", resource[:name]},
        {"deployment.environment", resource[:env]}
      ]
      |> Enum.reject(&is_nil(elem(&1, 1)))

    %{
      "resourceSpans" => [
        %{
          "resource" => %{"attributes" => Enum.map(attributes, &kv/1)},
          "scopeSpans" => [%{"scope" => %{"name" => "opentelemetry_phoenix"}, "spans" => spans}]
        }
      ]
    }
  end

  defp span(trace, id, parent, start, name, kind, status, opts) do
    attributes =
      [
        {"selected_account_handle", opts[:handle]},
        {"http.route", opts[:route]},
        {"error.type", opts[:error_type]}
      ]
      |> Enum.reject(&is_nil(elem(&1, 1)))

    %{
      "traceId" => id(trace),
      "spanId" => span_id(id),
      "name" => name,
      "kind" => kind,
      "startTimeUnixNano" => Integer.to_string(start),
      "endTimeUnixNano" => Integer.to_string(start + 1_000_000),
      "attributes" => Enum.map(attributes, &kv/1),
      "status" => %{"code" => status},
      "events" =>
        for event <- Keyword.get(opts, :exceptions, []) do
          %{
            "name" => "exception",
            "timeUnixNano" => Integer.to_string(start + 500_000),
            "attributes" => event |> Enum.sort() |> Enum.map(&kv/1)
          }
        end
    }
    |> then(&if(parent, do: Map.put(&1, "parentSpanId", span_id(parent)), else: &1))
  end

  defp kv({key, value}), do: %{"key" => key, "value" => %{"stringValue" => value}}
end
