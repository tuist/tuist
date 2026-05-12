defmodule Tuist.Webhooks.Workers.DeliveryWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Webhooks
  alias Tuist.Webhooks.Signature
  alias Tuist.Webhooks.Workers.DeliveryWorker

  defp build_job_args(opts \\ []) do
    %{plaintext: plaintext, encrypted: encrypted} = Webhooks.generate_signing_secret()

    %{
      args: %{
        "url" => Keyword.get(opts, :url, "https://example.com/hook"),
        "signing_secret_encrypted" => encrypted,
        "event_id" => Keyword.get(opts, :event_id, Ecto.UUID.generate()),
        "event_type" => Keyword.get(opts, :event_type, "test_case.updated"),
        "payload" => Keyword.get(opts, :payload, %{"foo" => "bar"})
      },
      plaintext_secret: plaintext
    }
  end

  test "POSTs the JSON envelope with HMAC headers on a 2xx" do
    %{args: args, plaintext_secret: secret} = build_job_args(payload: %{"id" => "evt_1"})

    expect(Req, :post, fn url, opts ->
      assert url == args["url"]
      body = Keyword.fetch!(opts, :body)
      assert body == JSON.encode!(%{"id" => "evt_1"})

      headers = Keyword.fetch!(opts, :headers)
      assert {"Content-Type", "application/json"} in headers
      assert {"User-Agent", "Tuist-Webhooks/1.0"} in headers
      assert {"Tuist-Event-Type", "test_case.updated"} in headers
      assert {"Tuist-Event-Id", args["event_id"]} in headers

      {_, signature} = Enum.find(headers, fn {k, _} -> k == "Tuist-Signature" end)
      assert :ok = Signature.verify(body, signature, secret)

      {:ok, %Req.Response{status: 200, body: "ok"}}
    end)

    assert :ok = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
  end

  test "returns {:error, _} on a non-2xx response so Oban retries" do
    %{args: args} = build_job_args()

    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 503, body: "unavailable"}}
    end)

    assert {:error, "HTTP 503"} = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
  end

  test "returns {:error, _} on a network error" do
    %{args: args} = build_job_args()

    expect(Req, :post, fn _url, _opts -> {:error, :timeout} end)

    assert {:error, :timeout} = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
  end

  test "discards the job when the signing secret is corrupt" do
    args = %{
      "url" => "https://example.com/hook",
      "signing_secret_encrypted" => "not-base64!!",
      "event_id" => Ecto.UUID.generate(),
      "event_type" => "test_case.updated",
      "payload" => %{}
    }

    assert {:discard, :invalid_signing_secret} =
             DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
  end

  describe "backoff/1" do
    test "follows the RFC schedule 1m → 5m → 30m → 2h → 8h → 24h" do
      expected = [60, 300, 1800, 7200, 28_800, 86_400]

      actual =
        for attempt <- 1..6 do
          DeliveryWorker.backoff(%Oban.Job{attempt: attempt})
        end

      assert actual == expected
    end
  end
end
