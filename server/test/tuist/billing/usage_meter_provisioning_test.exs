defmodule Tuist.Billing.UsageMeterProvisioningTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.UsageMeterProvisioning
  alias Tuist.Environment

  setup do
    stub(Environment, :stripe_api_key, fn -> "sk_test_key" end)
    :ok
  end

  defp stub_stripe(existing) do
    parent = self()

    stub(Stripe.Request, :make_request, fn request ->
      send(parent, {:request, request.method, request.endpoint, request.params})

      case {request.method, request.endpoint} do
        {:get, "/v1/billing/meters"} ->
          {:ok, %{data: Map.get(existing, :meters, [])}}

        {:post, "/v1/billing/meters"} ->
          {:ok, %{id: "mtr_#{request.params.event_name}"}}

        {:get, "/v1/prices"} ->
          [lookup_key] = request.params.lookup_keys
          {:ok, %{data: existing |> Map.get(:prices, %{}) |> Map.get(lookup_key, [])}}

        {:post, "/v1/prices"} ->
          {:ok, %{id: "price_#{request.params.lookup_key}"}}
      end
    end)
  end

  defp price(id, included, rate) do
    %{
      id: id,
      product: "prod_#{id}",
      tiers: [
        %{up_to: included, unit_amount: 0, unit_amount_decimal: "0"},
        %{up_to: nil, unit_amount: nil, unit_amount_decimal: rate}
      ]
    }
  end

  defp requests do
    receive do
      {:request, method, endpoint, params} -> [{method, endpoint, params} | requests()]
    after
      0 -> []
    end
  end

  describe "provision/1" do
    test "creates a Meter and a Price per meter, at the rates the pricing quotes" do
      stub_stripe(%{})

      assert UsageMeterProvisioning.provision() ==
               {:ok,
                %{
                  "cache_egress_megabytes" => "price_tuist_cache_egress_megabytes",
                  "cache_requests" => "price_tuist_cache_requests",
                  "passing_test_cases" => "price_tuist_passing_test_cases"
                }}

      posted_prices =
        requests()
        |> Enum.filter(&match?({:post, "/v1/prices", _}, &1))
        |> Enum.map(fn {_, _, params} -> {params.lookup_key, params.tiers, params.recurring.meter} end)

      assert posted_prices == [
               # $0.10 per GB is 0.01 cents per reported megabyte
               {"tuist_cache_egress_megabytes",
                [%{up_to: 100_000, unit_amount: 0}, %{up_to: "inf", unit_amount_decimal: "0.01"}],
                "mtr_cache_egress_megabytes"},
               # $0.01 per 1,000 requests
               {"tuist_cache_requests",
                [%{up_to: 1_000_000, unit_amount: 0}, %{up_to: "inf", unit_amount_decimal: "0.001"}],
                "mtr_cache_requests"},
               # $2 per million passing test cases
               {"tuist_passing_test_cases",
                [%{up_to: 5_000_000, unit_amount: 0}, %{up_to: "inf", unit_amount_decimal: "0.0002"}],
                "mtr_passing_test_cases"}
             ]
    end

    test "creates the Meter the reporting payload matches" do
      stub_stripe(%{})

      UsageMeterProvisioning.provision()

      assert {_, _, params} = Enum.find(requests(), &match?({:post, "/v1/billing/meters", _}, &1))
      assert params.default_aggregation == %{formula: "sum"}
      assert params.customer_mapping == %{type: "by_id", event_payload_key: "stripe_customer_id"}
      assert params.value_settings == %{event_payload_key: "value"}
    end

    test "answers with what is already provisioned instead of creating it again" do
      stub_stripe(%{
        meters: [
          %{id: "mtr_egress", event_name: "cache_egress_megabytes"},
          %{id: "mtr_requests", event_name: "cache_requests"},
          %{id: "mtr_tests", event_name: "passing_test_cases"}
        ],
        prices: %{
          "tuist_cache_egress_megabytes" => [price("price_egress", 100_000, "0.01")],
          "tuist_cache_requests" => [price("price_requests", 1_000_000, "0.001")],
          "tuist_passing_test_cases" => [price("price_tests", 5_000_000, "0.0002")]
        }
      })

      assert UsageMeterProvisioning.provision() ==
               {:ok,
                %{
                  "cache_egress_megabytes" => "price_egress",
                  "cache_requests" => "price_requests",
                  "passing_test_cases" => "price_tests"
                }}

      assert Enum.all?(requests(), &match?({:get, _, _}, &1))
    end

    test "replaces a Price whose rate no longer matches the pricing, taking over its lookup key" do
      stub_stripe(%{
        meters: [
          %{id: "mtr_egress", event_name: "cache_egress_megabytes"},
          %{id: "mtr_requests", event_name: "cache_requests"},
          %{id: "mtr_tests", event_name: "passing_test_cases"}
        ],
        prices: %{
          "tuist_cache_egress_megabytes" => [price("price_egress_old", 100_000, "0.035")],
          "tuist_cache_requests" => [price("price_requests", 1_000_000, "0.001")],
          "tuist_passing_test_cases" => [price("price_tests", 5_000_000, "0.0002")]
        }
      })

      assert {:ok, price_ids} = UsageMeterProvisioning.provision()
      assert price_ids["cache_egress_megabytes"] == "price_tuist_cache_egress_megabytes"
      assert price_ids["cache_requests"] == "price_requests"

      assert [{:post, "/v1/prices", params}] = Enum.filter(requests(), &match?({:post, _, _}, &1))
      assert params.lookup_key == "tuist_cache_egress_megabytes"
      assert params.transfer_lookup_key == true
      assert params.product == "prod_price_egress_old"
      refute Map.has_key?(params, :product_data)
      assert params.recurring.meter == "mtr_egress"
      assert List.last(params.tiers) == %{up_to: "inf", unit_amount_decimal: "0.01"}
    end

    test "refuses live mode unless it is asked for" do
      stub(Environment, :stripe_api_key, fn -> "sk_live_key" end)
      stub_stripe(%{})

      assert UsageMeterProvisioning.provision() == {:error, :refusing_live_mode_without_opt_in}
      assert requests() == []

      assert {:ok, _} = UsageMeterProvisioning.provision(live: true)
    end

    test "refuses an environment whose Stripe key is empty rather than reading it as live mode" do
      stub(Environment, :stripe_api_key, fn -> "" end)

      assert UsageMeterProvisioning.test_mode?() == nil
      assert UsageMeterProvisioning.provision(live: true) == {:error, :stripe_api_key_not_configured}
    end

    test "refuses an environment with no Stripe key" do
      stub(Environment, :stripe_api_key, fn -> nil end)

      assert UsageMeterProvisioning.provision(live: true) == {:error, :stripe_api_key_not_configured}
    end
  end
end
