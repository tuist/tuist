defmodule Tuist.Billing.StripeConfigTest do
  use ExUnit.Case, async: true
  use Mimic

  setup :set_mimic_from_context

  test "uses protocol version 1 for Stripe requests" do
    expect(:hackney, :request, fn :get, _url, _headers, "", options ->
      assert options[:protocols] == [:http1]

      {:ok, 401, [], ~s({"error":{"message":"Invalid key","type":"invalid_request_error"}})}
    end)

    assert {:error, %Stripe.Error{}} =
             Stripe.API.request(%{}, :get, "/customers", %{}, api_key: "invalid")
  end
end
