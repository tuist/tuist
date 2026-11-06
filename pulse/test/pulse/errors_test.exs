defmodule Pulse.ErrorsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.Errors
  alias Pulse.MCP.Tools
  alias Pulse.Record.Log
  alias Pulse.Storage

  @project %{"tenant" => "acme", "service" => "api"}
  @range %{"tenant" => "acme", "start_ts_ns" => 0, "end_ts_ns" => 100_000_000_000}

  defp record(id, seconds, fields \\ %{}, project \\ "1") do
    event =
      Map.merge(
        %{
          "event_id" => String.pad_leading(Integer.to_string(id, 16), 32, "0"),
          "timestamp" => seconds,
          "message" => "failed request #{id}"
        },
        fields
      )

    assert {:ok, record} = Errors.record(event, %{}, project, @project)
    record
  end

  defp query(name, fields \\ %{}) do
    assert {:ok, [%{"text" => text}]} = Tools.call(name, Map.merge(@range, fields))
    Pulse.JSON.decode!(text)
  end

  @tag :sentry_legacy_store
  test "offset-free Sentry timestamps mean UTC without repairing malformed or out-of-policy times" do
    for {value, expected} <- [
          {"2018-08-27T13:24:00", 1_535_376_240_000_000_000},
          {"2018-08-27T13:24:00Z", 1_535_376_240_000_000_000},
          {"2018-08-27T15:54:00+02:30", 1_535_376_240_000_000_000},
          {"2018-08-27T13:24:00.123456", 1_535_376_240_123_456_000}
        ] do
      assert {:ok, %Log{timestamp_ns: ^expected, body: %{"timestamp" => ^value}}} =
               Errors.record(%{"timestamp" => value}, %{}, "42", @project)
    end

    for value <- [
          "2018-08-27",
          "2018-02-30T13:24:00",
          "2018-08-27T24:00:00",
          "2018-08-27T13:24:00+00:0",
          "2018-08-27T13:24:00Zjunk",
          "1969-12-31T23:59:59",
          "2099-01-01T00:00:00",
          "2263-01-01T00:00:00"
        ] do
      assert {:error, :invalid_timestamp} = Errors.record(%{"timestamp" => value}, %{}, "42", @project)
    end
  end

  test "resource labels alone cannot turn malformed ordinary logs into errors" do
    valid = record(1, 10)
    assert Errors.error_record?(valid)

    malformed = [
      %{valid | body: "ordinary log"},
      %{valid | body: %{}},
      %{valid | body: %Log{}},
      %{valid | body: Map.put(valid.body, "event_id", String.duplicate("f", 32))},
      %{valid | resource: Map.drop(valid.resource, ["error_event_id", "error_issue_id"])},
      %{valid | resource: Map.put(valid.resource, "error_event_id", 123)},
      %{valid | resource: Map.put(valid.resource, "error_issue_id", "bad")},
      %{valid | resource: Map.put(valid.resource, "error_project", "bad/project")},
      %{valid | timestamp_ns: nil},
      %{valid | observed_timestamp_ns: nil},
      %{valid | service: nil}
    ]

    for row <- malformed, do: refute(Errors.error_record?(row))
    refute Errors.error_record?(nil)
    assert :ok = Storage.append(:logs, "acme", [valid | malformed])
    assert %{"matched_events" => 1, "results" => [%{"event_id" => id}]} = query("query_errors")
    assert id == valid.resource["error_event_id"]
    assert %{"matched_events" => 1, "results" => [%{"count" => 1}]} = query("list_error_issues")
  end

  test "issue counts are complete for the filtered window before result limiting and deduplicate retries" do
    records = [
      record(1, 10),
      record(2, 30),
      record(1, 10),
      record(3, 20, %{"fingerprint" => ["separate"]}),
      record(4, 40, %{"environment" => "staging"}),
      record(5, 90)
    ]

    :ok = Storage.append(:logs, "acme", records)

    assert %{"matched_events" => 4, "results" => [latest]} =
             query("list_error_issues", %{"end_ts_ns" => 50_000_000_000, "limit" => 1})

    assert latest["count"] == 3
    assert latest["issue_id"] == "v1_2ddf5aac04d52802a255fbfa72a906e0b6f4b8b456d4769e914c261ff8b98522"
    assert latest["first_seen_ns"] == 10_000_000_000
    assert latest["last_seen_ns"] == 40_000_000_000

    assert %{"matched_events" => 1, "results" => [%{"count" => 1}]} =
             query("list_error_issues", %{"environment" => "staging"})

    assert %{"results" => [%{"timestamp_ns" => 90_000_000_000}]} = query("query_errors", %{"limit" => 1})

    assert %{"results" => [%{"event_id" => id}]} =
             query("query_errors", %{"event_id" => Enum.at(records, 1).resource["error_event_id"]})

    assert id == Enum.at(records, 1).resource["error_event_id"]
  end

  test "conflicting retries use the compact index winner rather than lexical payload order" do
    records =
      for variant <- [7, 9] do
        record(
          1,
          10,
          %{
            "event_id" => String.duplicate("a", 32),
            "message" => "variant #{variant}",
            "fingerprint" => ["variant #{variant}"]
          },
          "42"
        )
      end

    :ok = Storage.append(:logs, "acme", records)

    assert %{"matched_events" => 1, "results" => [%{"event" => %{"message" => "variant 7"}, "issue_id" => issue}]} =
             query("query_errors")

    assert %{"results" => [%{"issue_id" => ^issue, "title" => "variant 7", "count" => 1}]} =
             query("list_error_issues")

    :ok = Storage.append(:logs, "acme", Enum.reverse(records))
    assert %{"results" => [%{"event" => %{"message" => "variant 7"}}]} = query("query_errors")
  end

  test "versioned grouping respects custom components, default expansion, stack sites and projects" do
    site = fn function, message ->
      %{
        "exception" => %{
          "values" => [
            %{
              "type" => "TypeError",
              "value" => message,
              "stacktrace" => %{"frames" => [%{"function" => function, "filename" => "app.ex", "in_app" => true}]}
            }
          ]
        }
      }
    end

    records = [
      record(1, 10, site.("save", "one")),
      record(2, 20, site.("save", "two")),
      record(3, 30, site.("load", "one")),
      record(4, 40, %{"fingerprint" => ["a|b", "c"]}),
      record(5, 50, %{"fingerprint" => ["a", "b|c"]}),
      record(6, 60, Map.put(site.("save", "one"), "fingerprint", ["{{ default }}", "extra"])),
      record(1, 70, site.("save", "one"), "2"),
      record(8, 80, Map.put(site.("save", "one"), "fingerprint", ["{{default}}"]))
    ]

    :ok = Storage.append(:logs, "acme", records)
    assert %{"results" => issues} = query("list_error_issues")
    assert length(issues) == 6
    assert Enum.count(issues, &(&1["count"] == 3)) == 1
    assert Enum.all?(issues, &String.starts_with?(&1["issue_id"], "v1_"))
    assert %{"matched_events" => 1} = query("query_errors", %{"project" => "2"})
  end

  test "a scan over 5000 occurrences errors even when only one result was requested" do
    records = Enum.map(1..5000, &record(&1, 10))
    :ok = Storage.append(:logs, "acme", records)
    assert %{"matched_events" => 5000, "results" => [%{"count" => 5000}]} = query("list_error_issues", %{"limit" => 1})
    :ok = Storage.append(:logs, "acme", [record(5001, 10)])

    for name <- ["query_errors", "list_error_issues"] do
      assert {:error, :query_sample_limit} = Tools.call(name, Map.put(@range, "limit", 1))
    end
  end

  test "event and issue pages preserve a fixed result snapshot without skips or duplicate counts" do
    :ok = Storage.append(:logs, "acme", [record(1, 10), record(2, 30), record(2, 30), record(3, 20)])

    first = query("query_errors", %{"limit" => 1})
    assert first["matched_events"] == 3
    assert first["matched_results"] == 3
    assert Enum.map(first["results"], & &1["timestamp_ns"]) == [30_000_000_000]

    second = query("query_errors", %{"cursor" => first["next_cursor"], "limit" => 2})
    assert second["snapshot_id"] == first["snapshot_id"]
    assert Enum.map(second["results"], & &1["timestamp_ns"]) == [20_000_000_000, 10_000_000_000]
    assert second["next_cursor"] == nil

    :ok = Storage.append(:logs, "acme", [record(4, 40, %{"fingerprint" => ["other"]})])
    issues = query("list_error_issues", %{"limit" => 1})
    assert issues["matched_results"] == 2
    assert Enum.map(issues["results"], & &1["count"]) == [1]
    last = query("list_error_issues", %{"cursor" => issues["next_cursor"]})
    assert Enum.map(last["results"], & &1["count"]) == [3]
    assert last["next_cursor"] == nil
  end

  test "cursors reject changed scopes, tampering, secret rotation and late arrivals" do
    :ok = Storage.append(:logs, "acme", [record(1, 10), record(2, 30)])
    cursor = query("query_errors", %{"limit" => 1})["next_cursor"]

    for {name, changes} <- [
          {"list_error_issues", %{}},
          {"query_errors", %{"tenant" => "other"}},
          {"query_errors", %{"project" => "1"}},
          {"query_errors", %{"end_ts_ns" => 90_000_000_000}},
          {"query_errors", %{"cursor" => cursor <> "tampered"}}
        ] do
      args = @range |> Map.put("cursor", cursor) |> Map.merge(changes)
      assert {:error, :error_query_reset_required} = Tools.call(name, args)
    end

    :ok = Storage.append(:logs, "acme", [record(3, 5)])
    assert {:error, :error_query_reset_required} = Tools.call("query_errors", Map.put(@range, "cursor", cursor))

    cursor = query("query_errors", %{"limit" => 1})["next_cursor"]
    config = Pulse.Runtime.fetch_env!(:pulse, PulseWeb.Endpoint)
    Pulse.Runtime.put_env(:pulse, PulseWeb.Endpoint, Keyword.put(config, :secret_key_base, String.duplicate("x", 64)))
    assert {:error, :error_query_reset_required} = Tools.call("query_errors", Map.put(@range, "cursor", cursor))
  end

  test "large payloads paginate by response bytes without losing event content" do
    message = String.duplicate("x", 800_000)
    :ok = Storage.append(:logs, "acme", for(id <- 1..3, do: record(id, id, %{"message" => message})))
    args = Map.put(@range, "limit", 5000)
    assert {:ok, [%{"text" => json}]} = Tools.call("query_errors", args)
    assert byte_size(json) <= 2_097_152
    first = Pulse.JSON.decode!(json)
    assert length(first["results"]) == 2
    assert first["matched_events"] == 3
    last = query("query_errors", %{"cursor" => first["next_cursor"]})

    assert Enum.map(first["results"] ++ last["results"], & &1["timestamp_ns"]) == [
             3_000_000_000,
             2_000_000_000,
             1_000_000_000
           ]

    assert Enum.all?(first["results"] ++ last["results"], &(&1["event"]["message"] == message))
    assert last["next_cursor"] == nil
  end

  test "error reads require tenant authorization before validation and DSN keys cannot grant reads" do
    Pulse.Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: %{})

    for name <- ["query_errors", "list_error_issues"] do
      assert {:error, {:unauthorized, :missing_token}} = Tools.call(name, %{"tenant" => "acme"})
      conn = Plug.Test.conn(:post, "/mcp") |> Plug.Conn.put_req_header("x-sentry-auth", "Sentry sentry_key=public-key")
      assert {:error, {:unauthorized, :missing_token}} = Tools.call(name, @range, %{conn: conn})
    end
  end

  test "project configuration fails closed and permits overlapping hashes for key rotation" do
    project = Map.put(@project, "public_key_hashes", [String.duplicate("a", 64), String.duplicate("b", 64)])
    assert Pulse.Sentry.validate_projects!(%{"42" => project}) == %{"42" => project}

    for domains <- [[], ["*"], [String.duplicate("a", 256)], List.duplicate("http://valid.com", 32)] do
      config = %{"42" => Map.put(project, "allowed_domains", domains)}
      assert Pulse.Sentry.validate_projects!(config) == config
    end

    for config <- [
          [],
          %{"../bad" => project},
          %{"42" => Map.put(project, "tenant", "bad/name")},
          %{"42" => Map.put(project, "public_key_hashes", [])},
          %{"42" => Map.put(project, "allowed_domains", nil)},
          %{"42" => Map.put(project, "allowed_domains", "*")},
          %{"42" => Map.put(project, "allowed_domains", [1])},
          %{"42" => Map.put(project, "allowed_domains", [""])},
          %{"42" => Map.put(project, "allowed_domains", [<<255>>])},
          %{"42" => Map.put(project, "allowed_domains", [String.duplicate("a", 257)])},
          %{"42" => Map.put(project, "allowed_domains", List.duplicate("*", 33))}
        ] do
      assert_raise ArgumentError, fn -> Pulse.Sentry.validate_projects!(config) end
    end
  end
end
