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

    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, _opts -> true end)
    :ok
  end

  test "legacy hand-out stays flagged while stable DNS is published for new clients" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
    observe(server, account)
    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: ^account] -> false end)

    assert StableEndpoint.resolve(account, [server.url]) == [server.url]

    assert StableEndpoint.intent(server, Regions.get(server.region)) == %{
             "stableHost" => StableEndpoint.host(account),
             "stableAWSRegion" => Regions.get(server.region).provisioner_config.aws_region,
             "stableAdvertise" => true
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

      assert StableEndpoint.intent(server, Regions.get(server.region))["stableAdvertise"]

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

  test "staging publishes stable DNS independently of legacy hand-out" do
    stub(Environment, :env, fn -> :stag end)
    selected = AccountsFixtures.user_fixture().account
    other = AccountsFixtures.user_fixture().account
    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: account] -> account.id == selected.id end)

    for account <- [selected, other] do
      {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
      server = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
      observe(server, account)
      enabled = account.id == selected.id

      assert StableEndpoint.intent(server, Regions.get(server.region))["stableAdvertise"]

      expected = if enabled, do: ["https://#{account.name}-staging.cache.tuist.dev"], else: [server.url]
      assert StableEndpoint.resolve(account, [server.url]) == expected
    end
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

  test "every managed public metro has a distinct AWS tag; private regions opt out" do
    mapping = %{
      "eu-west" => "eu-west-3",
      "us-east" => "us-east-1",
      "us-west" => "us-west-2",
      "ca-east" => "ca-central-1",
      "ap-southeast" => "ap-southeast-1",
      "sa-west" => "sa-east-1",
      "eu-east" => "eu-central-1",
      "us-central" => "us-east-2"
    }

    public_regions =
      Enum.filter(Regions.all(), &(not Regions.private?(&1) and &1.provisioner_config[:gateway] == :host_network))

    assert Enum.sort(Enum.map(public_regions, & &1.id)) == Enum.sort(Map.keys(mapping))
    assert length(Enum.uniq(Map.values(mapping))) == map_size(mapping)

    for {id, aws} <- mapping do
      assert StableEndpoint.supported?(Regions.get(id))
      assert Regions.get(id).provisioner_config.aws_region == aws
    end

    for region <- Enum.filter(Regions.all(), &Regions.private?/1) do
      refute StableEndpoint.supported?(region)
    end
  end

  for region <- ["sa-west", "eu-east", "us-central"] do
    test "stable hand-out includes ready placements in #{region}" do
      region = unquote(region)
      account = AccountsFixtures.user_fixture().account
      {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _} = PlacerRegions.put_secondary(account, region)
      source = KuraFixtures.active_server_fixture(account, region: "eu-west")
      destination = %{KuraFixtures.active_server_fixture(account, region: region) | account: account}
      urls = [source.url, destination.url]
      observe(source, account)
      assert StableEndpoint.resolve(account, urls) == urls

      observe(destination, account)
      assert StableEndpoint.resolve(account, urls) == ["https://#{account.name}.cache.tuist.dev"]
      assert StableEndpoint.intent(destination, Regions.get(region))["stableAdvertise"]
    end
  end

  test "unsupported survivors cannot authorize retirement of a stable endpoint" do
    account = AccountsFixtures.user_fixture().account
    private_region = Enum.find(Regions.all(), &Regions.private?/1)
    server = %Server{region: private_region.id}

    refute StableEndpoint.retirement_ready?(server, account)

    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: ^account] -> false end)
    refute StableEndpoint.retirement_ready?(server, account)
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

    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, _opts -> false end)
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

  test "disabling legacy hand-out does not withdraw DNS used by new clients" do
    account = AccountsFixtures.user_fixture().account
    {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
    server = %{KuraFixtures.active_server_fixture(account, region: "eu-west") | account: account}
    observe(server, account)
    assert StableEndpoint.resolve(account, [server.url]) == ["https://#{account.name}.cache.tuist.dev"]
    assert StableEndpoint.intent(server, Regions.get(server.region))["stableAdvertise"]

    stub(FunWithFlags, :enabled?, fn :kura_stable_hostname, [for: ^account] -> false end)

    assert StableEndpoint.resolve(account, [server.url]) == [server.url]

    assert StableEndpoint.intent(server, Regions.get(server.region)) == %{
             "stableHost" => StableEndpoint.host(account),
             "stableAWSRegion" => Regions.get(server.region).provisioner_config.aws_region,
             "stableAdvertise" => true
           }
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
