defmodule Pulse.OTLP.LogsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Logs
  alias Pulse.Record.Log

  test "accepts an empty request but rejects malformed containers" do
    assert Logs.decode(%{}) == {:ok, [], 0}
    assert Logs.decode(%{"resourceLogs" => "not-a-list"}) == {:error, :invalid_otlp}
  end

  test "decodes a full record with resource, attributes, and body" do
    payload = %{
      "resourceLogs" => [
        %{
          "resource" => %{
            "attributes" => [
              %{"key" => "service.name", "value" => %{"stringValue" => "api"}},
              %{"key" => "deploy.env", "value" => %{"stringValue" => "prod"}}
            ]
          },
          "scopeLogs" => [
            %{
              "scope" => %{"name" => "my.lib"},
              "logRecords" => [
                %{
                  "timeUnixNano" => "1700000000000000000",
                  "observedTimeUnixNano" => "1700000000000000001",
                  "severityNumber" => 9,
                  "severityText" => "INFO",
                  "body" => %{"stringValue" => "hello"},
                  "attributes" => [
                    %{"key" => "user.id", "value" => %{"stringValue" => "u1"}}
                  ],
                  "traceId" => String.duplicate("a", 32),
                  "spanId" => String.duplicate("d", 16)
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok,
            [
              %Log{
                timestamp_ns: 1_700_000_000_000_000_000,
                observed_timestamp_ns: 1_700_000_000_000_000_001,
                severity_number: 9,
                severity_text: "INFO",
                service: "api",
                body: "hello",
                trace_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                span_id: "dddddddddddddddd",
                attributes: %{"user.id" => "u1"},
                resource: %{"service.name" => "api", "deploy.env" => "prod"}
              }
            ], 0} = Logs.decode(payload)
  end

  test "preserves absent timestamps as nil so storage can backfill deterministically" do
    # OTLP allows both timestamps to be absent, and a zero value means
    # "unknown". The decoder does NOT invent a wall-clock value here —
    # that would defeat the caller_content_hash for a retry. The storage
    # adapter fills in a stored timestamp later.
    payload = %{
      "resourceLogs" => [
        %{
          "scopeLogs" => [
            %{"logRecords" => [%{"body" => %{"stringValue" => "no ts"}}]}
          ]
        }
      ]
    }

    assert {:ok, [%Log{timestamp_ns: nil, observed_timestamp_ns: nil, body: "no ts"}], 0} =
             Logs.decode(payload)
  end

  test "preserves an observed-only timestamp verbatim" do
    payload = %{
      "resourceLogs" => [
        %{
          "scopeLogs" => [
            %{
              "logRecords" => [
                %{
                  "observedTimeUnixNano" => "42",
                  "body" => %{"stringValue" => "only observed"}
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, [%Log{timestamp_ns: 42, observed_timestamp_ns: 42, body: "only observed"}], 0} =
             Logs.decode(payload)
  end

  test "folds a zero timestamp to nil per the OTLP spec" do
    # `time_unix_nano: 0` means "unknown", identical in meaning to the
    # field being absent. If the decoder left it as 0, the record would
    # be stored at the Unix epoch and vanish from time-bounded queries.
    payload = %{
      "resourceLogs" => [
        %{
          "scopeLogs" => [
            %{
              "logRecords" => [
                %{
                  "timeUnixNano" => "0",
                  "observedTimeUnixNano" => "1700000000000000000",
                  "body" => %{"stringValue" => "zero ts"}
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, [%Log{timestamp_ns: 1_700_000_000_000_000_000, observed_timestamp_ns: 1_700_000_000_000_000_000}], 0} =
             Logs.decode(payload)
  end

  test "counts a non-map logRecords entry as rejected" do
    # A logRecord entry that is not a map is genuinely malformed — the
    # decoder cannot invent fields, so it counts toward rejected.
    payload = %{
      "resourceLogs" => [
        %{
          "scopeLogs" => [
            %{
              "logRecords" => [
                "not-a-map",
                %{"timeUnixNano" => "1", "body" => %{"stringValue" => "ok"}}
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, [%Log{body: "ok"}], 1} = Logs.decode(payload)
  end

  test "decodes AnyValue variants in attributes" do
    payload = %{
      "resourceLogs" => [
        %{
          "scopeLogs" => [
            %{
              "logRecords" => [
                %{
                  "timeUnixNano" => "1",
                  "attributes" => [
                    %{"key" => "s", "value" => %{"stringValue" => "x"}},
                    %{"key" => "i", "value" => %{"intValue" => "42"}},
                    %{"key" => "b", "value" => %{"boolValue" => true}},
                    %{"key" => "d", "value" => %{"doubleValue" => 3.14}},
                    %{
                      "key" => "arr",
                      "value" => %{
                        "arrayValue" => %{
                          "values" => [%{"stringValue" => "a"}, %{"intValue" => "1"}]
                        }
                      }
                    },
                    %{
                      "key" => "kv",
                      "value" => %{
                        "kvlistValue" => %{
                          "values" => [%{"key" => "n", "value" => %{"intValue" => "7"}}]
                        }
                      }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, [%Log{attributes: attrs}], 0} = Logs.decode(payload)
    assert attrs["s"] == "x"
    assert attrs["i"] == 42
    assert attrs["b"] == true
    assert attrs["d"] == 3.14
    assert attrs["arr"] == ["a", 1]
    assert attrs["kv"] == %{"n" => 7}
  end

  test "flattens multiple resourceLogs and scopeLogs entries" do
    payload = %{
      "resourceLogs" => [
        %{
          "resource" => %{
            "attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "a"}}]
          },
          "scopeLogs" => [
            %{"logRecords" => [%{"timeUnixNano" => "1"}, %{"timeUnixNano" => "2"}]},
            %{"logRecords" => [%{"timeUnixNano" => "3"}]}
          ]
        },
        %{
          "resource" => %{
            "attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "b"}}]
          },
          "scopeLogs" => [%{"logRecords" => [%{"timeUnixNano" => "4"}]}]
        }
      ]
    }

    assert {:ok, records, 0} = Logs.decode(payload)
    assert length(records) == 4
    assert Enum.map(records, & &1.service) == ["a", "a", "a", "b"]
    assert Enum.map(records, & &1.timestamp_ns) == [1, 2, 3, 4]
  end
end
