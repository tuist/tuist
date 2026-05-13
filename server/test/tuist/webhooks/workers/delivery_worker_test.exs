defmodule Tuist.Webhooks.Workers.DeliveryWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Webhooks
  alias Tuist.Webhooks.Signature
  alias Tuist.Webhooks.Workers.DeliveryWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp build_endpoint do
    account = AccountsFixtures.user_fixture().account

    {:ok, endpoint, plaintext} =
      Webhooks.create_endpoint(account.id, %{
        "name" => "Hook",
        "url" => "https://example.com/hook",
        "event_types" => ["test_case.updated"]
      })

    %{endpoint: endpoint, plaintext: plaintext}
  end

  defp job_args(endpoint, opts \\ []) do
    %{
      "webhook_endpoint_id" => endpoint.id,
      "event_id" => Keyword.get(opts, :event_id, Ecto.UUID.generate()),
      "event_type" => Keyword.get(opts, :event_type, "test_case.updated"),
      "payload" => Keyword.get(opts, :payload, %{"foo" => "bar"})
    }
  end

  test "POSTs the JSON envelope with HMAC headers on a 2xx" do
    %{endpoint: endpoint, plaintext: secret} = build_endpoint()
    args = job_args(endpoint, payload: %{"id" => "evt_1"})

    expect(Req, :post, fn url, opts ->
      assert url == endpoint.url
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
    %{endpoint: endpoint} = build_endpoint()

    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 503, body: "unavailable"}}
    end)

    assert {:error, "HTTP 503"} = DeliveryWorker.perform(%Oban.Job{args: job_args(endpoint), attempt: 1})
  end

  test "returns {:error, _} on a network error" do
    %{endpoint: endpoint} = build_endpoint()
    expect(Req, :post, fn _url, _opts -> {:error, :timeout} end)
    assert {:error, :timeout} = DeliveryWorker.perform(%Oban.Job{args: job_args(endpoint), attempt: 1})
  end

  test "discards the job when the endpoint no longer exists" do
    %{endpoint: endpoint} = build_endpoint()
    {:ok, _} = Webhooks.delete_endpoint(endpoint)

    assert {:discard, :endpoint_not_found} =
             DeliveryWorker.perform(%Oban.Job{args: job_args(endpoint), attempt: 1})
  end

  test "re-reads the endpoint per attempt so secret rotations take effect" do
    %{endpoint: endpoint, plaintext: original} = build_endpoint()
    {:ok, _rotated, new_secret} = Webhooks.rotate_signing_secret(endpoint)
    refute original == new_secret

    expect(Req, :post, fn _url, opts ->
      body = Keyword.fetch!(opts, :body)
      headers = Keyword.fetch!(opts, :headers)
      {_, signature} = Enum.find(headers, fn {k, _} -> k == "Tuist-Signature" end)
      # Signature is computed against the rotated secret, not the original one.
      assert :ok = Signature.verify(body, signature, new_secret)
      assert {:error, _} = Signature.verify(body, signature, original)
      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    assert :ok = DeliveryWorker.perform(%Oban.Job{args: job_args(endpoint), attempt: 2})
  end

  describe "backoff/1" do
    test "follows the RFC schedule 1m → 5m → 30m → 2h → 8h → 24h" do
      expected = [60, 300, 1800, 7200, 28_800, 86_400]
      actual = for attempt <- 1..6, do: DeliveryWorker.backoff(%Oban.Job{attempt: attempt})
      assert actual == expected
    end
  end
end
