defmodule TuistWeb.API.TelemetryControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Pulse
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  @envelope ~s({"event_id":"9ec79c33ec9942ab8353589fcb2e04dc"}\n{"type":"event"}\n{"message":"boom"}\n)
  @pulse "http://pulse.observability.svc.cluster.local:4000"

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    stub(Pulse, :own_telemetry?, fn -> true end)

    stub(Environment, :sentry_pulse_dsn, fn ->
      "http://sentry:writer-secret@pulse.observability.svc.cluster.local:4000/v1/sentry/server/1"
    end)

    %{user: user, bearer: sign_in(user, %{id: Clients.luft_client_id()})}
  end

  defp sign_in(user, client) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    bearer
  end

  defp post_otlp(conn, bearer, signal, body, content_type \\ "application/json") do
    body = if is_map(body), do: JSON.encode!(body), else: body

    conn
    |> put_req_header("authorization", "Bearer #{bearer}")
    |> put_req_header("content-type", content_type)
    |> post("/api/telemetry/v1/#{signal}", body)
  end

  defp attribute(key, value), do: %{"key" => key, "value" => %{"stringValue" => value}}

  defp now, do: System.system_time(:nanosecond)

  # Typed as Luft never sends it: Pulse would type the column by it.
  defp spans(start \\ now()),
    do: %{
      "resourceSpans" => [
        %{
          "resource" => %{"attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "server"}}]},
          "scopeSpans" => [
            %{
              "scope" => %{
                "name" => "tuist-app-core",
                "attributes" => [%{"key" => "k", "value" => %{"stringValue" => "v"}}]
              },
              "spans" => [
                %{
                  "traceId" => "5B8EFFF798038103D269B633813FC60C",
                  "spanId" => "eee19b7ec3c1b174",
                  "name" => "threads",
                  "kind" => 3,
                  "startTimeUnixNano" => Integer.to_string(start),
                  "endTimeUnixNano" => start + 250_000_000,
                  "status" => %{"code" => 2, "message" => "boom"},
                  "attributes" => [
                    %{"key" => "http.response.status_code", "value" => %{"intValue" => "503"}},
                    %{"key" => "user.email", "value" => %{"stringValue" => "ana@example.com"}},
                    %{"key" => "luft.outcome", "value" => %{"boolValue" => true}}
                  ],
                  "events" => [%{"name" => "e", "timeUnixNano" => "1"}],
                  "unknownField" => true
                }
              ]
            }
          ]
        }
      ]
    }

  defp decoded_spans(body) do
    %{resource_spans: [%{resource: resource, scope_spans: [%{scope: scope, spans: [span]}]}]} =
      :opentelemetry_exporter_trace_service_pb.decode_msg(body, :export_trace_service_request)

    {resource, scope, span}
  end

  test "forwards OTLP/JSON spans as protobuf, confined to the luft-client service, and answers in JSON",
       %{conn: conn, bearer: bearer} do
    start = now()

    expect(Req, :request, fn request ->
      assert URI.to_string(request.url) == "#{@pulse}/v1/otlp/v1/traces"
      assert request.headers["authorization"] == ["Basic " <> Base.encode64("sentry:writer-secret")]
      assert request.headers["x-pulse-trace-table-name"] == ["opentelemetry_traces"]
      assert request.headers["x-pulse-db-name"] == ["public"]

      {resource, scope, span} = decoded_spans(request.body)
      # A sender can't claim another service, add columns or keep span events.
      assert Enum.map(resource.attributes, &{&1.key, &1.value.value}) == [
               {"service.name", {:string_value, "luft-client"}}
             ]

      assert scope == %{name: "tuist-app-core", version: "", attributes: [], dropped_attributes_count: 0}
      assert span.trace_id == Base.decode16!("5B8EFFF798038103D269B633813FC60C")
      assert span.kind == :SPAN_KIND_CLIENT
      assert span.end_time_unix_nano == start + 250_000_000
      assert span.status.code == :STATUS_CODE_ERROR
      assert [%{key: "http.response.status_code", value: %{value: {:int_value, 503}}}] = span.attributes
      assert span.events == []
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    conn = post_otlp(conn, bearer, "traces", spans(start))
    assert response(conn, 200) == "{}"
    assert get_resp_header(conn, "content-type") == ["application/json"]
  end

  test "takes gzipped binary protobuf and answers with the signal's protobuf response",
       %{conn: conn, bearer: bearer} do
    body =
      :opentelemetry_exporter_logs_service_pb.encode_msg(
        %{
          resource_logs: [
            %{
              scope_logs: [
                %{
                  log_records: [
                    %{
                      time_unix_nano: now(),
                      body: %{value: {:string_value, "boot: ready"}},
                      attributes: [
                        %{key: "luft.operation", value: %{value: {:string_value, "threads"}}},
                        %{key: "path", value: %{value: {:string_value, "/Users/ana"}}}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        },
        :export_logs_service_request
      )

    expect(Req, :request, fn request ->
      assert URI.to_string(request.url) == "#{@pulse}/v1/otlp/v1/logs"
      assert request.headers["x-pulse-log-table-name"] == ["opentelemetry_logs"]

      %{resource_logs: [%{scope_logs: [%{log_records: [record]}]}]} =
        :opentelemetry_exporter_logs_service_pb.decode_msg(request.body, :export_logs_service_request)

      assert record.body.value == {:string_value, "boot: ready"}
      assert Enum.map(record.attributes, & &1.key) == ["luft.operation"]
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    conn =
      conn
      |> put_req_header("content-encoding", "gzip")
      |> post_otlp(bearer, "logs", :zlib.gzip(body), "application/x-protobuf")

    assert get_resp_header(conn, "content-type") == ["application/x-protobuf"]

    assert :opentelemetry_exporter_logs_service_pb.decode_msg(response(conn, 200), :export_logs_service_response) ==
             %{}
  end

  defp sum(points, extra \\ %{}),
    do: Map.merge(%{"aggregationTemporality" => 1, "isMonotonic" => true, "dataPoints" => points}, extra)

  test "keeps only Luft's counter, with known labels, as a partial success", %{conn: conn, bearer: bearer} do
    point = fn attributes -> %{"asInt" => "3", "timeUnixNano" => Integer.to_string(now()), "attributes" => attributes} end
    labels = [attribute("luft.operation", "threads"), attribute("luft.outcome", "ok")]

    metrics = %{
      "resourceMetrics" => [
        %{
          # Pulse promotes service.version to a label, so metrics carry none.
          "resource" => %{
            "attributes" => [attribute("service.version", "random-1"), attribute("service.namespace", "kube")]
          },
          "scopeMetrics" => [
            %{
              "metrics" => [
                %{
                  "name" => "luft.core.operations",
                  "unit" => "{operation}",
                  "sum" =>
                    sum([
                      point.(labels),
                      # An invented operation is folded into one series; an extra
                      # label or an unknown outcome is a new one and is rejected.
                      point.([attribute("luft.operation", "aaaabbbb"), attribute("luft.outcome", "ok")]),
                      point.([attribute("tenant", "x") | labels]),
                      point.([attribute("luft.operation", "threads"), attribute("luft.outcome", "maybe")]),
                      %{point.(labels) | "timeUnixNano" => "1763400000000000000"}
                    ])
                },
                # Pulse names tables after the kind and unit: a histogram or a
                # cumulative sum of the same name would be new tables.
                %{
                  "name" => "luft.core.operations",
                  "unit" => "zzz_attacker",
                  "histogram" => %{
                    "aggregationTemporality" => 2,
                    "dataPoints" => [Map.merge(point.(labels), %{"count" => "2", "explicitBounds" => [1.5]})]
                  }
                },
                %{"name" => "luft.core.operations", "sum" => sum([point.(labels)], %{"aggregationTemporality" => 2})},
                %{"name" => "up", "gauge" => %{"dataPoints" => [point.([])]}},
                # A sum without points is nothing to reject, not a crash.
                %{"name" => "luft.core.operations", "sum" => %{"aggregationTemporality" => 1, "isMonotonic" => true}}
              ]
            }
          ]
        }
      ]
    }

    expect(Req, :request, fn request ->
      assert URI.to_string(request.url) == "#{@pulse}/v1/otlp/v1/metrics"
      refute Map.has_key?(request.headers, "x-pulse-trace-table-name")

      %{resource_metrics: [%{resource: resource, scope_metrics: [%{metrics: [metric, empty]}]}]} =
        :opentelemetry_exporter_metrics_service_pb.decode_msg(request.body, :export_metrics_service_request)

      assert Enum.map(resource.attributes, &{&1.key, &1.value.value}) == [
               {"service.name", {:string_value, "luft-client"}}
             ]

      assert metric.name == "luft.core.operations"
      assert metric.unit == ""
      assert {:sum, %{aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA, data_points: points}} = metric.data

      assert Enum.map(points, fn point -> Enum.map(point.attributes, & &1.value.value) end) == [
               [{:string_value, "threads"}, {:string_value, "ok"}],
               [{:string_value, "other"}, {:string_value, "ok"}]
             ]

      assert {:sum, %{data_points: []}} = empty.data
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    assert %{"partialSuccess" => %{"rejectedDataPoints" => "6", "errorMessage" => message}} =
             conn |> post_otlp(bearer, "metrics", metrics) |> json_response(200)

    assert message =~ "accepted metrics"
  end

  test "masks span names that aren't Luft's and rejects spans far from now", %{conn: conn, bearer: bearer} do
    span = fn name, start ->
      %{
        "traceId" => "5b8efff798038103d269b633813fc60c",
        "spanId" => "eee19b7ec3c1b174",
        "name" => name,
        "startTimeUnixNano" => Integer.to_string(start)
      }
    end

    names = ["threads", "GET /api/accounts/*/threads", "GET /api/accounts/ana/threads", "ana@example.com"]
    old = now() - 8 * 86_400 * 1_000_000_000

    body = %{
      "resourceSpans" => [
        %{"scopeSpans" => [%{"spans" => Enum.map(names, &span.(&1, now())) ++ [span.("threads", old)]}]}
      ]
    }

    expect(Req, :request, fn request ->
      %{resource_spans: [%{scope_spans: [%{spans: spans}]}]} =
        :opentelemetry_exporter_trace_service_pb.decode_msg(request.body, :export_trace_service_request)

      assert Enum.map(spans, & &1.name) == ["threads", "GET /api/accounts/*/threads", "other", "other"]
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    assert %{"partialSuccess" => %{"rejectedSpans" => "1"}} =
             conn |> post_otlp(bearer, "traces", body) |> json_response(200)
  end

  test "refuses batches too large to forward", %{conn: conn, bearer: bearer} do
    reject(&Req.request/1)
    text = String.duplicate("x", 250)

    span = %{
      "name" => "threads",
      "startTimeUnixNano" => Integer.to_string(now()),
      "status" => %{"message" => text},
      "attributes" => [attribute("luft.error", text)]
    }

    # Encodes past 1 MiB after confinement: refused before Pulse sees it.
    spans = %{"resourceSpans" => [%{"scopeSpans" => [%{"spans" => List.duplicate(span, 3000)}]}]}
    conn = post_otlp(conn, bearer, "traces", spans)
    assert %{"code" => 8} = json_response(conn, 413)

    # Protobuf past what a request may carry isn't read whole.
    oversized = :binary.copy(<<0>>, 4_100_000)
    assert build_conn() |> post_otlp(bearer, "traces", oversized, "application/x-protobuf") |> response(413)
  end

  test "rejects malformed requests as final, with a google.rpc.Status", %{conn: conn, bearer: bearer} do
    reject(&Req.request/1)
    path = ["resourceSpans", Access.at(0), "scopeSpans", Access.at(0), "spans", Access.at(0)]

    for body <- [
          put_in(spans(), path ++ ["traceId"], "zz"),
          put_in(spans(), path ++ ["kind"], 42),
          put_in(spans(), path ++ ["kind"], "SPAN_KIND_NOPE"),
          %{"resourceSpans" => "x"}
        ] do
      assert %{"code" => 3, "message" => _} = conn |> post_otlp(bearer, "traces", body) |> json_response(400)
    end

    conn = post_otlp(build_conn(), bearer, "traces", "not protobuf", "application/x-protobuf")
    assert conn |> response(400) |> String.starts_with?(<<0x08, 3>>)

    assert build_conn() |> post_otlp(bearer, "traces", "x", "text/plain") |> response(415)
    assert build_conn() |> post_otlp(bearer, "profiles", spans()) |> json_response(404)
  end

  test "throttles with 429 and Retry-After, without the app session's shared limit",
       %{conn: conn, bearer: bearer, user: user} do
    reject(&Req.request/1)
    key = "telemetry:requests:user:#{user.id}"

    stub(RateLimit, :hit, fn
      ^key, opts ->
        assert opts[:algorithm] == :token_bucket
        # What the shared limiter answers for any token-bucket denial.
        {:deny, 1_000}

      other, _opts ->
        flunk("unexpected limit #{other}")
    end)

    conn = post_otlp(conn, bearer, "traces", spans())
    assert %{"code" => 8} = json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") == ["1"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{bearer}")
      |> put_req_header("content-type", "application/x-sentry-envelope")
      |> post("/api/telemetry/api/1/envelope/", @envelope)

    assert json_response(conn, 429)["detail"]
    assert get_resp_header(conn, "x-sentry-rate-limits") == ["1::organization"]
  end

  test "limits the bytes forwarded per user and across all users", %{conn: conn, bearer: bearer, user: user} do
    reject(&Req.request/1)
    user_key = "telemetry:kib:user:#{user.id}"

    stub(RateLimit, :hit, fn
      ^user_key, opts ->
        assert opts[:cost] == 1
        {:allow, 1}

      "telemetry:kib", _opts ->
        {:deny, 60_000}

      _key, _opts ->
        {:allow, 1}
    end)

    conn = post_otlp(conn, bearer, "traces", spans())
    assert json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") == ["60"]
  end

  test "asks for a wait that refills the batch's bytes", %{conn: conn, bearer: bearer, user: user} do
    reject(&Req.request/1)
    user_key = "telemetry:kib:user:#{user.id}"

    stub(RateLimit, :hit, fn
      ^user_key, opts -> if opts[:cost] > 16, do: {:deny, 1_000}, else: {:allow, 1}
      _key, _opts -> {:allow, 1}
    end)

    text = String.duplicate("x", 250)

    span = %{
      "name" => "threads",
      "startTimeUnixNano" => Integer.to_string(now()),
      "status" => %{"message" => text},
      "attributes" => [attribute("luft.error", text)]
    }

    body = %{"resourceSpans" => [%{"scopeSpans" => [%{"spans" => List.duplicate(span, 1000)}]}]}

    conn = post_otlp(conn, bearer, "traces", body)
    assert json_response(conn, 429)
    # About 520 KiB at 16 KiB/s, not the limiter's one second.
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) in 30..40
  end

  test "forwards Luft's Sentry envelopes, gzipped or not, as luft-client errors", %{conn: conn, bearer: bearer} do
    expect(Req, :request, 2, fn request ->
      assert URI.to_string(request.url) == "#{@pulse}/v1/sentry/luft-client/api/1/envelope/"
      assert request.headers["content-type"] == ["application/x-sentry-envelope"]
      refute Map.has_key?(request.headers, "content-encoding")
      assert request.body == @envelope
      {:ok, %Req.Response{status: 200, body: ~s({"id":"9ec79c33ec9942ab8353589fcb2e04dc"})}}
    end)

    for {encoding, body} <- [{nil, @envelope}, {"gzip", :zlib.gzip(@envelope)}] do
      conn =
        conn
        |> recycle()
        |> put_req_header("authorization", "Bearer #{bearer}")
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> then(&if encoding, do: put_req_header(&1, "content-encoding", encoding), else: &1)
        |> post("/api/telemetry/api/1/envelope/", body)

      assert json_response(conn, 200) == %{"id" => "9ec79c33ec9942ab8353589fcb2e04dc"}
    end
  end

  test "Luft envelopes cannot bypass the OTLP producer policy with other item types", %{conn: conn, bearer: bearer} do
    # A length-delimited attachment may contain text that looks like event framing.
    attachment = ~s(\n{"type":"event"}\n{"message":"not an event"}\n)

    body =
      @envelope <>
        ~s({"type":"log"}\n{"items":[{"body":"private","attributes":{"email":"private"}}]}\n) <>
        ~s({"type":"span"}\n{"name":"GET /private/path","timestamp":1}\n) <>
        ~s({"type":"transaction"}\n{"transaction":"private","spans":[]}\n) <>
        ~s({"type":"session"}\n{"sid":"private"}\n) <>
        JSON.encode!(%{type: "attachment", length: byte_size(attachment)}) <> "\n" <> attachment

    expect(Req, :request, fn request ->
      assert request.body == @envelope
      {:ok, %Req.Response{status: 200, body: "{}"}}
    end)

    assert conn
           |> put_req_header("authorization", "Bearer #{bearer}")
           |> put_req_header("content-type", "application/x-sentry-envelope")
           |> post("/api/telemetry/api/1/envelope/", body)
           |> json_response(200) == %{}
  end

  test "rejects malformed Sentry framing before forwarding", %{conn: conn, bearer: bearer} do
    reject(&Req.request/1)

    for body <- [
          "[]\n",
          "{}\n[]\n{}\n",
          ~s({}\n{"type":"event","length":-1}\n{}\n),
          ~s({}\n{"type":"attachment","length":999}\nshort)
        ] do
      assert conn
             |> recycle()
             |> put_req_header("authorization", "Bearer #{bearer}")
             |> put_req_header("content-type", "application/x-sentry-envelope")
             |> post("/api/telemetry/api/1/envelope/", body)
             |> json_response(400)
    end
  end

  test "preserves Pulse category backoff on accepted and rejected envelopes", %{conn: conn, bearer: bearer} do
    for status <- [200, 429] do
      expect(Req, :request, fn _ ->
        {:ok,
         %Req.Response{
           status: status,
           body: "{}",
           headers: %{
             "retry-after" => ["37"],
             "x-sentry-rate-limits" => ["37:error:organization"],
             "set-cookie" => ["not-forwarded=true"]
           }
         }}
      end)

      response =
        conn
        |> recycle()
        |> put_req_header("authorization", "Bearer #{bearer}")
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post("/api/telemetry/api/1/envelope/", @envelope)

      assert response.status == status
      assert get_resp_header(response, "retry-after") == ["37"]
      assert get_resp_header(response, "x-sentry-rate-limits") == ["37:error:organization"]
      assert get_resp_header(response, "set-cookie") == []
    end
  end

  test "refuses, without retry, a user blocked from sending", %{conn: conn, user: user, bearer: bearer} do
    # Only the user who isn't blocked reaches Pulse.
    expect(Req, :request, fn _ -> {:ok, %Req.Response{status: 200, body: ""}} end)
    other = AccountsFixtures.user_fixture()
    stub(Tuist.FeatureFlags, :telemetry_blocked?, &(&1.id == user.id))

    assert %{"code" => 7} = conn |> post_otlp(bearer, "traces", spans()) |> json_response(403)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{bearer}")
      |> put_req_header("content-type", "application/x-sentry-envelope")
      |> post("/api/telemetry/api/1/envelope/", @envelope)

    assert %{"detail" => _} = json_response(conn, 403)

    # The block is the user's alone.
    assert build_conn() |> post_otlp(sign_in(other, %{id: Clients.luft_client_id()}), "traces", spans()) |> response(200)
  end

  test "admits only Luft's own session", %{conn: conn, user: user} do
    reject(&Req.request/1)
    app_bearer = sign_in(user, Clients.public!())

    assert conn |> post_otlp(app_bearer, "traces", spans()) |> json_response(403)
    assert build_conn() |> post("/api/telemetry/v1/traces", spans()) |> json_response(401)
  end

  test "answers 404 while this server has no Pulse for Luft", %{conn: conn, bearer: bearer} do
    reject(&Req.request/1)
    stub(Pulse, :own_telemetry?, fn -> false end)

    assert conn |> post_otlp(bearer, "logs", %{}) |> json_response(404)
  end

  test "reports Pulse's own failures as retryable", %{conn: conn, bearer: bearer} do
    expect(Req, :request, fn _ -> {:ok, %Req.Response{status: 401, body: ""}} end)
    assert %{"code" => 14} = conn |> post_otlp(bearer, "traces", spans()) |> json_response(502)

    expect(Req, :request, fn _ -> {:error, %Req.TransportError{reason: :econnrefused}} end)
    assert build_conn() |> post_otlp(bearer, "traces", spans()) |> json_response(503)

    expect(Req, :request, fn _ -> {:ok, %Req.Response{status: 429, body: ""}} end)
    conn = post_otlp(build_conn(), bearer, "traces", spans())
    assert json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") == ["30"]
  end
end
