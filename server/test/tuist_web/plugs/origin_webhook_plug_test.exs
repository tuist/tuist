defmodule TuistWeb.Plugs.OriginWebhookPlugTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Origin.Auth
  alias Tuist.Origin.WebhookWorker
  alias TuistWeb.Plugs.OriginWebhookPlug

  test "verified envelopes, not routing headers, choose the app and installation; retries deduplicate" do
    stub(Environment, :origin_app_credentials, fn -> %{app_id: "app-tuist"} end)
    stub(Auth, :verify_webhook, fn _, _ -> {:ok, "delivery-1"} end)

    envelope = %{
      "deliveryId" => "delivery-1",
      "appId" => "app-tuist",
      "installationId" => "signed-installation",
      "event" => %{"id" => "event-1", "type" => "installation.updated", "payload" => %{"private" => "not-retained"}}
    }

    for _ <- 1..2 do
      conn =
        :post
        |> Plug.Test.conn("/webhooks/origin", JSON.encode!(envelope))
        |> Plug.Conn.put_req_header("webhook-installation-id", "attacker-installation")
        |> OriginWebhookPlug.call([])

      assert conn.status == 202
    end

    assert [job] = all_enqueued(worker: WebhookWorker)
    assert job.args["installationId"] == "signed-installation"
    refute job.args["event"]["payload"]

    conn =
      :post
      |> Plug.Test.conn("/webhooks/origin", JSON.encode!(%{envelope | "appId" => "another-app"}))
      |> OriginWebhookPlug.call([])

    assert conn.status == 403
  end
end
