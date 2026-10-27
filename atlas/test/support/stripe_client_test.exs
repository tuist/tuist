defmodule Atlas.TestSupport.StripeClientTest do
  use ExUnit.Case, async: true

  alias Atlas.TestSupport.StripeClient

  test "prefers customer-specific invoice fixtures over the generic fallback" do
    StripeClient.put_list_invoices(fn {_customer_id, [limit: 100]} -> {:error, :generic} end)
    StripeClient.put_list_invoices("cus_specific", fn [limit: 100] -> {:ok, %{data: ["specific"]}} end)

    assert StripeClient.list_invoices("cus_specific", limit: 100) == {:ok, %{data: ["specific"]}}
    assert StripeClient.list_invoices("cus_other", limit: 100) == {:error, :generic}
  end
end
