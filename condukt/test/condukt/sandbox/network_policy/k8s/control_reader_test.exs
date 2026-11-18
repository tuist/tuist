defmodule Condukt.Sandbox.NetworkPolicy.K8s.ControlReaderTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.NetworkPolicy.Event
  alias Condukt.Sandbox.NetworkPolicy.K8s.ControlReader

  describe "decode_line/1" do
    test "decodes a full event" do
      line =
        JSON.encode!(%{
          "kind" => "request_closed",
          "request" => %{
            "id" => "r1",
            "host" => "api.github.com",
            "port" => 443,
            "started_at" => "2026-05-14T10:00:00Z",
            "finished_at" => "2026-05-14T10:00:01Z",
            "bytes_in" => 200,
            "bytes_out" => 50
          },
          "at" => "2026-05-14T10:00:01Z"
        })

      assert {:ok, %Event{kind: :request_closed, request: request, reason: nil}} =
               ControlReader.decode_line(line)

      assert request.host == "api.github.com"
      assert request.bytes_in == 200
    end

    test "decodes a denial event with reason" do
      line =
        JSON.encode!(%{
          "kind" => "request_denied",
          "request" => %{
            "id" => "r2",
            "host" => "evil.com",
            "port" => 443,
            "started_at" => "2026-05-14T10:00:00Z"
          },
          "reason" => "no_allow_match"
        })

      assert {:ok, %Event{kind: :request_denied, reason: "no_allow_match"}} =
               ControlReader.decode_line(line)
    end

    test "decodes a request_failed event" do
      line =
        JSON.encode!(%{
          "kind" => "request_failed",
          "request" => %{
            "id" => "r3",
            "host" => "api.github.com",
            "port" => 443,
            "started_at" => "2026-05-14T10:00:00Z"
          },
          "reason" => "tls_client_rejected_ca"
        })

      assert {:ok, %Event{kind: :request_failed, reason: "tls_client_rejected_ca"}} =
               ControlReader.decode_line(line)
    end

    test "decodes matched_rule provenance" do
      line =
        JSON.encode!(%{
          "kind" => "request_denied",
          "request" => %{
            "id" => "r4",
            "host" => "evil.com",
            "port" => 443,
            "started_at" => "2026-05-14T10:00:00Z"
          },
          "reason" => "matched_deny_list",
          "matched_rule" => %{"index" => 2, "kind" => "deny"}
        })

      assert {:ok, %Event{matched_rule: %{index: 2, kind: :deny}}} =
               ControlReader.decode_line(line)
    end

    test "matched_rule is nil when absent" do
      line =
        JSON.encode!(%{
          "kind" => "request_allowed",
          "request" => %{
            "id" => "r5",
            "host" => "api.github.com",
            "port" => 443,
            "started_at" => "2026-05-14T10:00:00Z"
          }
        })

      assert {:ok, %Event{matched_rule: nil}} = ControlReader.decode_line(line)
    end

    test "rejects malformed lines" do
      assert {:error, _} = ControlReader.decode_line("not json")
      assert {:error, _} = ControlReader.decode_line(JSON.encode!(%{"foo" => "bar"}))
      assert {:error, _} = ControlReader.decode_line(JSON.encode!(%{"kind" => "bogus", "request" => %{}}))
    end
  end
end
