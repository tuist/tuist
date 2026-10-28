defmodule TuistWeb.Plugs.OriginWebhookPlugTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Test

  alias Tuist.Environment
  alias Tuist.Origin.Signatures
  alias TuistWeb.Plugs.OriginWebhookPlug

  setup do
    stub(Environment, :origin_app_id, fn -> "app_tuist" end)
    :ok
  end

  test "inserts verified lifecycle events durably before acknowledging" do
    body = delivery()

    expect(Signatures, :verify_webhook, fn ^body, headers ->
      assert headers["webhook-id"] == "whd_test"
      :ok
    end)

    expect(Oban, :insert, fn changeset ->
      assert Ecto.Changeset.get_field(changeset, :args) == %{
               delivery_id: "whd_test",
               installation_id: "i_test"
             }

      assert Ecto.Changeset.get_field(changeset, :queue) == "vcs_comments"
      {:ok, %Oban.Job{}}
    end)

    conn =
      :post |> conn("/webhooks/origin", body) |> Plug.Conn.put_req_header("webhook-id", "whd_test")

    assert %{status: 202, halted: true} = OriginWebhookPlug.call(conn, [])
  end

  test "failed durable acceptance returns 503 for redelivery" do
    stub(Signatures, :verify_webhook, fn _, _ -> :ok end)
    stub(Oban, :insert, fn _ -> {:error, :database_unavailable} end)

    conn =
      :post
      |> conn("/webhooks/origin", delivery())
      |> Plug.Conn.put_req_header("webhook-id", "whd_test")

    assert %{status: 503} = OriginWebhookPlug.call(conn, [])
  end

  test "invalid signatures, mismatched app IDs, and mismatched delivery IDs are rejected" do
    reject(&Oban.insert/1)
    stub(Signatures, :verify_webhook, fn _, _ -> {:error, :invalid_origin_signature} end)

    assert %{status: 401} =
             OriginWebhookPlug.call(conn(:post, "/webhooks/origin", delivery()), [])

    stub(Signatures, :verify_webhook, fn _, _ -> :ok end)

    for body <- [delivery("app_other"), delivery()] do
      assert %{status: 401} = OriginWebhookPlug.call(conn(:post, "/webhooks/origin", body), [])
    end
  end

  test "a signing-key outage returns a retryable status" do
    stub(Signatures, :verify_webhook, fn _, _ -> {:error, :origin_keys_unavailable} end)

    assert %{status: 503} =
             OriginWebhookPlug.call(conn(:post, "/webhooks/origin", delivery()), [])
  end

  test "unsigned routing headers cannot override the signed event type" do
    stub(Signatures, :verify_webhook, fn _, _ -> :ok end)
    reject(&Oban.insert/1)
    body = delivery() |> JSON.decode!() |> put_in(["event", "type"], "ping") |> JSON.encode!()

    conn =
      :post
      |> conn("/webhooks/origin", body)
      |> Plug.Conn.put_req_header("webhook-id", "whd_test")
      |> Plug.Conn.put_req_header("webhook-event-type", "installation.deleted")

    assert %{status: 204} = OriginWebhookPlug.call(conn, [])
  end

  test "accepts Origin's signed app-level ping without an installation" do
    stub(Signatures, :verify_webhook, fn _, _ -> :ok end)
    reject(&Oban.insert/1)
    body = JSON.encode!(%{appId: "app_tuist", deliveryId: "whd_test", event: %{type: "ping"}})

    conn =
      :post |> conn("/webhooks/origin", body) |> Plug.Conn.put_req_header("webhook-id", "whd_test")

    assert %{status: 204} = OriginWebhookPlug.call(conn, [])
  end

  test "other endpoint paths pass through untouched" do
    conn = conn(:post, "/webhooks/github", "{}")
    assert ^conn = OriginWebhookPlug.call(conn, [])
  end

  defp delivery(app_id \\ "app_tuist") do
    JSON.encode!(%{
      appId: app_id,
      deliveryId: "whd_test",
      installationId: "i_test",
      event: %{type: "installation.deleted"}
    })
  end
end
