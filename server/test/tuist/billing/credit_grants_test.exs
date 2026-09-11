defmodule Tuist.Billing.CreditGrantsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Billing.CreditGrants

  describe "create/1" do
    test "scopes the grant to the given prices and stamps the money on it" do
      expires_at = ~U[2027-08-18 00:00:00Z]
      expires_at_unix = DateTime.to_unix(expires_at)

      expect(Stripe.Request, :make_request, fn %{
                                                 method: :post,
                                                 endpoint: "/v1/billing/credit_grants",
                                                 headers: %{"Idempotency-Key" => "runner-prepaid-in_1"},
                                                 params: %{
                                                   customer: "cus_1",
                                                   amount: %{
                                                     type: "monetary",
                                                     monetary: %{currency: "usd", value: 1_250_000}
                                                   },
                                                   applicability_config: %{
                                                     scope: %{prices: [%{id: "price_macos"}, %{id: "price_linux"}]}
                                                   },
                                                   category: "paid",
                                                   name: "Prepaid runner credit",
                                                   priority: 50,
                                                   expires_at: ^expires_at_unix
                                                 }
                                               } ->
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, %{id: "credgr_1"}} =
               CreditGrants.create(%{
                 customer_id: "cus_1",
                 amount_cents: 1_250_000,
                 currency: "USD",
                 price_ids: ["price_macos", "price_linux"],
                 category: "paid",
                 name: "Prepaid runner credit",
                 priority: 50,
                 expires_at: expires_at,
                 idempotency_key: "runner-prepaid-in_1"
               })
    end

    test "omits the optional terms it was not given" do
      expect(Stripe.Request, :make_request, fn %{params: params, headers: headers} ->
        refute Map.has_key?(params, :expires_at)
        refute Map.has_key?(params, :name)
        refute Map.has_key?(params, :priority)
        refute Map.has_key?(headers, "Idempotency-Key")
        assert params.category == "paid"

        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _grant} =
               CreditGrants.create(%{
                 customer_id: "cus_1",
                 amount_cents: 100,
                 currency: "usd",
                 price_ids: ["price_macos"]
               })
    end

    test "refuses a grant that could never pay for anything" do
      invalid = [
        %{customer_id: "cus_1", amount_cents: 0, currency: "usd", price_ids: ["price_macos"]},
        %{customer_id: "cus_1", amount_cents: -100, currency: "usd", price_ids: ["price_macos"]},
        %{customer_id: "cus_1", amount_cents: 100, currency: "usd", price_ids: []}
      ]

      for attrs <- invalid do
        assert_raise FunctionClauseError, fn -> CreditGrants.create(attrs) end
      end
    end
  end

  describe "list_for_customer/1" do
    test "pages through the collection so a dedup check cannot miss an older grant" do
      first_page = Enum.map(1..100, &%{id: "credgr_#{&1}"})

      expect(Stripe.Request, :make_request, fn %{
                                                 method: :get,
                                                 endpoint: "/v1/billing/credit_grants",
                                                 params: %{customer: "cus_1", limit: 100} = params
                                               } ->
        refute Map.has_key?(params, :starting_after)
        {:ok, %{data: first_page, has_more: true}}
      end)

      expect(Stripe.Request, :make_request, fn %{params: %{starting_after: "credgr_100"}} ->
        {:ok, %{data: [%{id: "credgr_101"}], has_more: false}}
      end)

      assert {:ok, grants} = CreditGrants.list_for_customer("cus_1")
      assert length(grants) == 101
      assert List.last(grants).id == "credgr_101"
    end

    test "propagates a Stripe failure rather than reporting an empty history" do
      expect(Stripe.Request, :make_request, fn _request -> {:error, :timeout} end)

      assert {:error, :timeout} = CreditGrants.list_for_customer("cus_1")
    end
  end

  describe "available_balance_cents/2" do
    test "reads the drawn-down balance for one grant" do
      expect(Stripe.Request, :make_request, fn %{
                                                 method: :get,
                                                 endpoint: "/v1/billing/credit_balance_summary",
                                                 params: %{
                                                   customer: "cus_1",
                                                   filter: %{type: "credit_grant", credit_grant: "credgr_1"}
                                                 }
                                               } ->
        {:ok,
         %{
           balances: [
             %{
               available_balance: %{type: "monetary", monetary: %{currency: "usd", value: 750}},
               ledger_balance: %{type: "monetary", monetary: %{currency: "usd", value: 1000}}
             }
           ]
         }}
      end)

      assert {:ok, 750} = CreditGrants.available_balance_cents("cus_1", "credgr_1")
    end

    test "reports zero when Stripe returns no balances" do
      expect(Stripe.Request, :make_request, fn _request -> {:ok, %{balances: []}} end)

      assert {:ok, 0} = CreditGrants.available_balance_cents("cus_1", "credgr_1")
    end
  end
end
