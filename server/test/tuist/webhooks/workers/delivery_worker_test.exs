defmodule Tuist.Webhooks.Workers.DeliveryWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Webhooks
  alias Tuist.Webhooks.DeliveryAttempt
  alias Tuist.Webhooks.Signature
  alias Tuist.Webhooks.Workers.DeliveryWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    # SSRFGuard.pin/1 does live DNS — tests assert against `endpoint.url`
    # directly, so we stub the guard to return the URL untouched. The
    # SSRF behaviour itself has its own coverage in `ssrf_guard_test.exs`.
    stub(SSRFGuard, :pin, fn url ->
      %URI{host: host} = URI.parse(url)
      {:ok, url, host}
    end)

    stub(SSRFGuard, :connect_options, fn _hostname -> [] end)

    account = AccountsFixtures.user_fixture().account

    {:ok, endpoint, plaintext} =
      Webhooks.create_endpoint(account.id, %{
        "name" => "Hook",
        "url" => "https://example.com/hook",
        "event_types" => ["test_case.updated"]
      })

    event_id = Ecto.UUID.generate()

    args = %{
      "webhook_endpoint_id" => endpoint.id,
      "event_id" => event_id,
      "event_type" => "test_case.updated",
      "payload" => %{"foo" => "bar"}
    }

    %{endpoint: endpoint, plaintext: plaintext, event_id: event_id, args: args}
  end

  test "POSTs the JSON envelope with HMAC headers on a 2xx", %{
    endpoint: endpoint,
    plaintext: secret,
    args: args
  } do
    args = put_in(args["payload"], %{"id" => "evt_1"})

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

  test "returns {:error, _} on a non-2xx response so Oban retries", %{args: args} do
    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 503, body: "unavailable"}}
    end)

    assert {:error, "HTTP 503"} = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
  end

  test "returns {:error, _} on a network error", %{args: args} do
    expect(Req, :post, fn _url, _opts -> {:error, :timeout} end)
    assert {:error, :timeout} = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
  end

  test "discards the job when the endpoint no longer exists", %{
    endpoint: endpoint,
    args: args
  } do
    {:ok, _} = Webhooks.delete_endpoint(endpoint)

    assert {:discard, :endpoint_not_found} =
             DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
  end

  test "re-reads the endpoint per attempt so secret rotations take effect", %{
    endpoint: endpoint,
    plaintext: original,
    args: args
  } do
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

    assert :ok = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 2})
  end

  describe "attempt persistence" do
    test "buffers a delivered row carrying the attempt number on the retry path", %{
      endpoint: endpoint,
      event_id: event_id,
      args: args
    } do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: "ok"}}
      end)

      expect(DeliveryAttempt.Buffer, :insert, fn row ->
        assert row.webhook_endpoint_id == endpoint.id
        assert row.event_id == event_id
        assert row.event_type == "test_case.updated"
        # Retry attempts persist with the matching counter so the
        # dashboard can show the per-attempt history.
        assert row.attempt == 4
        assert row.status == "delivered"
        assert row.response_status == 200
        assert row.error == ""
        :ok
      end)

      assert :ok = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 4})
    end

    test "records the upstream status and error message on a non-2xx response", %{
      endpoint: endpoint,
      event_id: event_id,
      args: args
    } do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 503, body: "unavailable"}}
      end)

      expect(DeliveryAttempt.Buffer, :insert, fn row ->
        assert row.webhook_endpoint_id == endpoint.id
        assert row.event_id == event_id
        assert row.attempt == 2
        assert row.status == "failed"
        assert row.response_status == 503
        assert row.error == "HTTP 503"
        :ok
      end)

      assert {:error, "HTTP 503"} = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 2})
    end

    test "records a network error with `response_status: 0`", %{
      endpoint: endpoint,
      event_id: event_id,
      args: args
    } do
      expect(Req, :post, fn _url, _opts -> {:error, :timeout} end)

      expect(DeliveryAttempt.Buffer, :insert, fn row ->
        assert row.webhook_endpoint_id == endpoint.id
        assert row.event_id == event_id
        assert row.attempt == 3
        assert row.status == "failed"
        assert row.response_status == 0
        assert row.error == ":timeout"
        :ok
      end)

      assert {:error, :timeout} = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 3})
    end

    test "redacts the Tuist-Signature header from the persisted row", %{args: args} do
      expect(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      expect(DeliveryAttempt.Buffer, :insert, fn row ->
        headers = JSON.decode!(row.request_headers)
        assert headers["Tuist-Signature"] == "[redacted]"
        # Non-sensitive headers are kept intact so the dashboard remains useful.
        assert headers["Content-Type"] == "application/json"
        assert headers["User-Agent"] == "Tuist-Webhooks/1.0"
        :ok
      end)

      assert :ok = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
    end

    test "redacts sensitive response headers (set-cookie, authorization, …)", %{args: args} do
      expect(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           headers: %{
             "set-cookie" => "session=secret",
             "authorization" => "Bearer abc",
             "X-Trace-Id" => "tr-1"
           },
           body: ""
         }}
      end)

      expect(DeliveryAttempt.Buffer, :insert, fn row ->
        headers = JSON.decode!(row.response_headers)
        assert headers["set-cookie"] == "[redacted]"
        assert headers["authorization"] == "[redacted]"
        # Non-sensitive headers pass through unchanged.
        assert headers["X-Trace-Id"] == "tr-1"
        :ok
      end)

      assert :ok = DeliveryWorker.perform(%Oban.Job{args: args, attempt: 1})
    end
  end

  describe "backoff/1" do
    test "follows the RFC schedule 1m → 5m → 30m → 2h → 8h → 24h" do
      expected = [60, 300, 1800, 7200, 28_800, 86_400]
      actual = for attempt <- 1..6, do: DeliveryWorker.backoff(%Oban.Job{attempt: attempt})
      assert actual == expected
    end
  end
end
