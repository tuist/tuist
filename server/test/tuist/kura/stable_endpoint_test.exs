defmodule Tuist.Kura.StableEndpointTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Registrations
  alias Tuist.Kura.StableEndpoint
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.KuraFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :kura_stable_hostname_enabled?, fn -> true end)
    stub(Environment, :kura_stable_hostname_handout_enabled?, fn -> true end)
    stub(Environment, :kura_stable_hostname_accounts, fn -> [] end)
    :ok
  end

  test "environment suffixes and reserved handles cannot collide" do
    for {env, suffix} <- [prod: "", stag: "-staging", can: "-canary"] do
      stub(Environment, :env, fn -> env end)
      assert StableEndpoint.host(%Account{name: "Acme"}) == "acme#{suffix}.cache.tuist.dev"
      assert StableEndpoint.host(%Account{name: "acme-STAGING"}) == nil
      assert StableEndpoint.host(%Account{name: "acme-canary"}) == nil
    end

    stub(Environment, :env, fn -> :dev end)
    assert StableEndpoint.host(%Account{name: "acme"}) == nil
  end

  test "all five managed metros have distinct AWS tags; private regions opt out" do
    mapping = %{
      "eu-west" => "eu-west-3",
      "us-east" => "us-east-1",
      "us-west" => "us-west-2",
      "ca-east" => "ca-central-1",
      "ap-southeast" => "ap-southeast-1"
    }

    for {id, aws} <- mapping do
      assert StableEndpoint.supported?(Regions.get(id))
      assert Regions.get(id).provisioner_config.aws_region == aws
    end

    for region <- Enum.filter(Regions.all(), &Regions.private?/1) do
      refute StableEndpoint.supported?(region)
    end
  end

  test "collapse waits for every desired region and keeps custom URLs" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    {:ok, _} = PlacerRegions.put_secondary(account, "ca-east")
    paris = KuraFixtures.active_server_fixture(account, region: "eu-west")
    montreal = KuraFixtures.active_server_fixture(account, region: "ca-east")
    urls = [paris.url, montreal.url, "https://cache.example.com"]
    observe(paris, account)
    assert StableEndpoint.resolve(account, urls) == urls
    observe(montreal, account)

    assert StableEndpoint.resolve(account, urls) == [
             "https://#{account.name}.cache.tuist.dev",
             "https://cache.example.com"
           ]

    # A frozen status read does not renew its controller timestamp.
    observe(montreal, account, checked_at: DateTime.add(DateTime.utc_now(), -181))
    assert StableEndpoint.resolve(account, urls) == urls
    observe(montreal, account, generation: 2)
    assert StableEndpoint.resolve(account, urls) == urls
  end

  test "account endpoint response keeps registered and custom peers beside the stable entry" do
    stub(Environment, :tuist_hosted?, fn -> true end)
    account = AccountsFixtures.user_fixture().account
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
    {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})
    {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://custom.example.com"})

    {:ok, _} =
      Registrations.register_heartbeat(account, %{
        node_id: "self-hosted",
        advertised_http_url: "https://registered.example.com",
        ready: true
      })

    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")
    observe(server, account)

    assert Accounts.kura_cache_endpoint_urls(account) == [
             "https://#{account.name}.cache.tuist.dev",
             "https://registered.example.com",
             "https://custom.example.com"
           ]

    stub(Environment, :kura_stable_hostname_handout_enabled?, fn -> false end)
    assert Accounts.kura_cache_endpoint_urls(account) == [server.url, "https://registered.example.com"]
  end

  test "demotion leaves intent unchanged and drain withdraws while rendering" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    {:ok, _} = PlacerRegions.put_secondary(account, "ca-east")
    paris = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
    region = Regions.get("eu-west")
    before = StableEndpoint.intent(paris, region)
    {:ok, _} = PlacerRegions.put_primary(account, "ca-east")
    assert StableEndpoint.intent(paris, region) == before
    draining = StableEndpoint.intent(%{paris | status: :drain_pending}, region)
    assert draining["stableHost"] == before["stableHost"]
    refute draining["stableAdvertise"]
  end

  test "hand-out, rendering, and account allowlist gates are independent" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
    observe(server, account)
    stub(Environment, :kura_stable_hostname_handout_enabled?, fn -> false end)
    assert StableEndpoint.resolve(account, [server.url]) == [server.url]
    assert StableEndpoint.intent(server, Regions.get(server.region))["stableAdvertise"]
    stub(Environment, :kura_stable_hostname_accounts, fn -> ["another-account"] end)
    refute StableEndpoint.intent(server, Regions.get(server.region))["stableAdvertise"]
    stub(Environment, :kura_stable_hostname_accounts, fn -> [] end)
    stub(Environment, :kura_stable_hostname_enabled?, fn -> false end)
    assert StableEndpoint.intent(server, Regions.get(server.region))["stableHost"] == ""
  end

  defp observe(server, account, opts \\ []) do
    host = StableEndpoint.host(account)

    StableEndpoint.observe(server.region, server.provisioner_node_ref, %{
      "metadata" => %{"generation" => Keyword.get(opts, :generation, 1)},
      "spec" => %{"stableHost" => host, "stableAdvertise" => true},
      "status" => %{
        "stableEndpoint" => %{
          "host" => host,
          "ready" => true,
          "observedGeneration" => 1,
          "lastCheckedAt" => DateTime.to_iso8601(Keyword.get(opts, :checked_at, DateTime.utc_now()))
        }
      }
    })
  end
end
