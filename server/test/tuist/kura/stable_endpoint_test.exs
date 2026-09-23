defmodule Tuist.Kura.StableEndpointTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Demand
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Registrations
  alias Tuist.Kura.Server
  alias Tuist.Kura.StableEndpoint
  alias Tuist.Kura.Workers.ProvisionOnDemandWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.KuraFixtures
  alias TuistTestSupport.TelemetryCapture

  setup :set_mimic_from_context

  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :kura_stable_hostname_enabled?, fn -> true end)
    stub(Environment, :kura_stable_hostname_handout_enabled?, fn -> true end)
    stub(Environment, :kura_stable_hostname_accounts, fn -> [] end)
    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, _opts -> true end)
    :ok
  end

  test "production without the feature flag keeps regional URLs and publishes no stable intent" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
    observe(server, account)
    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: ^account] -> false end)

    assert StableEndpoint.resolve(account, [server.url]) == [server.url]

    assert StableEndpoint.intent(server, Regions.get(server.region)) == %{
             "stableHost" => "",
             "stableAWSRegion" => "",
             "stableAdvertise" => false
           }
  end

  test "production account opt-in does not enable another account" do
    opted_in = AccountsFixtures.user_fixture().account
    other = AccountsFixtures.user_fixture().account

    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: account] -> account.id == opted_in.id end)

    for account <- [opted_in, other] do
      {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
      server = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
      observe(server, account)
      enabled = account.id == opted_in.id

      assert StableEndpoint.intent(server, Regions.get(server.region))["stableAdvertise"] == enabled

      expected = if enabled, do: ["https://#{account.name}.cache.tuist.dev"], else: [server.url]
      assert StableEndpoint.resolve(account, [server.url]) == expected
    end
  end

  test "canary advertises and hands out a ready stable endpoint without a production flag" do
    stub(Environment, :env, fn -> :can end)
    reject(FunWithFlags, :enabled?, 2)
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
    observe(server, account)

    assert StableEndpoint.intent(server, Regions.get(server.region))["stableAdvertise"]
    assert StableEndpoint.resolve(account, [server.url]) == ["https://#{account.name}-canary.cache.tuist.dev"]
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

  test "custom endpoints do not bypass an archived account's provisioning and fallback" do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> ["eu-west"] end)
    stub(Environment, :cache_endpoints, fn -> ["https://legacy.example.com"] end)

    for technology <- [:kura, :kura_with_legacy_fallback] do
      account = AccountsFixtures.user_fixture().account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})
      {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://custom.example.com"})
      {:ok, _} = Demand.upsert(account.id, "eu-west", DateTime.utc_now())

      Repo.insert!(%Server{
        account_id: account.id,
        region: "eu-west",
        status: :archived,
        provisioner_node_ref: "kura-#{account.id}-eu-west"
      })

      endpoints = if technology == :kura, do: [], else: ["https://legacy.example.com"]

      assert Accounts.get_cache_resolution_for_handle(account.name, technology) ==
               %{endpoints: endpoints, provisioning: true}

      assert_enqueued(worker: ProvisionOnDemandWorker, args: %{account_id: account.id})
    end
  end

  test "custom endpoints wait for stable hand-out, even with a serving managed instance" do
    stub(Environment, :tuist_hosted?, fn -> true end)
    account = AccountsFixtures.user_fixture().account
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
    {:ok, account} = Accounts.update_account(account, %{custom_cache_endpoints_enabled: true})
    {:ok, _} = Accounts.create_account_cache_endpoint(account, %{url: "https://custom.example.com"})
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")

    assert Accounts.kura_cache_endpoint_urls(account) == [server.url]
  end

  test "readiness tolerates bounded clock skew without accepting far-future observations" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")
    observe(server, account, checked_at: DateTime.add(DateTime.utc_now(), 20))
    assert StableEndpoint.resolve(account, [server.url]) == ["https://#{account.name}.cache.tuist.dev"]
    observe(server, account, checked_at: DateTime.add(DateTime.utc_now(), 60))
    assert StableEndpoint.resolve(account, [server.url]) == [server.url]
  end

  test "observing unchanged controller state does not rewrite the projection" do
    account = AccountsFixtures.user_fixture().account
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")
    checked_at = DateTime.utc_now()
    assert {1, _} = observe(server, account, checked_at: checked_at)
    assert {0, _} = observe(server, account, checked_at: checked_at)
  end

  test "endpoint resolution reads managed servers and the feature flag once" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")
    observe(server, account)
    flag_read = make_ref()

    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: ^account] ->
      send(self(), flag_read)
      true
    end)

    ref = TelemetryCapture.attach_event_handlers([[:tuist, :repo, :query]])

    assert Accounts.kura_cache_endpoint_urls(account) == ["https://#{account.name}.cache.tuist.dev"]
    assert_received ^flag_read
    refute_received ^flag_read

    {:messages, messages} = Process.info(self(), :messages)
    queries = for {[:tuist, :repo, :query], ^ref, _, %{query: query}} <- messages, do: query
    assert Enum.count(queries, &String.contains?(&1, ~s(FROM "kura_servers"))) == 1
  end

  test "stable reconciliation overlaps independent instance requests" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")

    for region <- ["eu-west", "ca-east"] do
      KuraFixtures.active_server_fixture(account, region: region)
    end

    owner = self()

    stub(KubernetesController, :sync_stable_endpoint, fn server, _region, _claimed ->
      send(owner, {:syncing, self(), server.id})

      receive do
        :continue -> :ok
      after
        5_000 -> raise "independent stable endpoint requests were serialized"
      end
    end)

    task = Task.async(fn -> StableEndpoint.reconcile() end)

    try do
      assert_receive {:syncing, first, _}, 1_000
      assert_receive {:syncing, second, _}, 1_000
      assert first != second
      send(first, :continue)
      send(second, :continue)
      Task.await(task)
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  test "a reader without the reconciler's local cache still hands out the stable endpoint" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")
    observe(server, account)

    Cachex.del(:tuist, "kura_stable_endpoint-#{server.region}-#{server.provisioner_node_ref}")

    assert StableEndpoint.resolve(account, [server.url]) == ["https://#{account.name}.cache.tuist.dev"]
  end

  test "archival clears stable readiness before a cold return" do
    account = AccountsFixtures.user_fixture().account
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")
    observe(server, account)
    server = Repo.reload!(server)
    assert StableEndpoint.ready?(server, StableEndpoint.host(account))

    {:ok, draining} = Kura.begin_drain(server)
    {:ok, archived} = Kura.archive_server(draining)

    assert archived.stable_endpoint == nil
    refute StableEndpoint.ready?(Repo.reload!(archived), StableEndpoint.host(account))
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
