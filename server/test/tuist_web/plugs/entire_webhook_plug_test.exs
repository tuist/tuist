defmodule TuistWeb.Plugs.EntireWebhookPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Entire
  alias Tuist.Entire.Client
  alias TuistWeb.Plugs.EntireWebhookPlug

  setup do
    stub(Client, :configured?, fn -> true end)
    :ok
  end

  test "queues a verified body before acknowledging it" do
    body = ~s({"delivery_id": "delivery"})
    expect(Client, :verify_delivery, fn "signed-token", ^body -> {:ok, %{"delivery_id" => "delivery"}, "jwt-id"} end)
    expect(Entire, :accept_delivery, fn %{"delivery_id" => "delivery"}, "jwt-id" -> {:ok, :stored} end)
    conn = request(body)
    assert conn.status == 200
    assert conn.halted
  end

  test "distinguishes an invalid signature from retryable JWKS or persistence failure" do
    stub(Client, :verify_delivery, fn _, _ -> {:error, :invalid_delivery} end)
    assert request("{}").status == 401
    stub(Client, :verify_delivery, fn _, _ -> {:error, :unavailable} end)
    assert request("{}").status == 503
    stub(Client, :verify_delivery, fn _, _ -> {:ok, %{}, "jwt-id"} end)
    stub(Entire, :accept_delivery, fn _, _ -> {:error, :database_unavailable} end)
    assert request("{}").status == 503
  end

  test "rejects missing authorization and oversized bodies without processing" do
    reject(&Client.verify_delivery/2)
    conn = :post |> Plug.Test.conn("/webhooks/entire", "{}") |> EntireWebhookPlug.call([])
    assert conn.status == 401
    assert request(String.duplicate("a", 262_145)).status == 413
  end

  defp request(body) do
    :post
    |> Plug.Test.conn("/webhooks/entire", body)
    |> put_req_header("authorization", "Bearer signed-token")
    |> EntireWebhookPlug.call([])
  end
end
