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

  test "retries a request that reached a connection closing in the pool" do
    expect(:hackney, :request, fn :get, _url, _headers, "", _options -> {:error, :invalid_state} end)

    expect(:hackney, :request, fn :get, _url, _headers, "", _options ->
      {:ok, 200, [], ~s({"id":"cus_123","object":"customer"})}
    end)

    assert {:ok, %{"id" => "cus_123"}} =
             Stripe.API.request(%{}, :get, "/customers/cus_123", %{}, api_key: "sk_test")
  end

  test "retries a closing pooled connection only once" do
    expect(:hackney, :request, 2, fn :get, _url, _headers, "", _options -> {:error, :invalid_state} end)

    assert {:error, %Stripe.Error{source: :network, extra: %{hackney_reason: :invalid_state}}} =
             Stripe.API.request(%{}, :get, "/customers/cus_123", %{}, api_key: "sk_test")
  end
end
