defmodule Tuist.Shards.StorageTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Runners.CacheGrant
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.Storage, as: ShardStorage
  alias Tuist.Storage
  alias Tuist.Storage.S3Target

  setup do
    config = %{
      "site" => "gra",
      "enabled" => true,
      "private_network_ready" => true,
      "endpoint" => "http://shard-storage.kura.svc.cluster.local:3900",
      "bucket" => "shards",
      "access_key_id" => "test-key",
      "secret_access_key" => "test-secret"
    }

    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => config} end)
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> true end)
    stub(FeatureFlags, :public_shard_storage_enabled?, fn _ -> false end)
    key = JOSE.JWK.generate_key({:okp, :Ed25519})
    pem = JOSE.JWK.to_pem(key)
    pem = if is_tuple(pem), do: elem(pem, 1), else: pem
    stub(Environment, :cache_grant_private_key, fn -> pem end)
    grant = CacheGrant.mint(42, site: "gra", platform: :linux)
    %{config: config, account: %Account{id: 42}, project: %Project{build_system: :mix}, grant: grant}
  end

  test "selects a ready store only for an enrolled signed Linux runner", ctx do
    expect(Storage, :available?, fn %S3Target{id: "gra-v1"} -> true end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == "gra-v1"
  end

  test "a Linux runner's plan goes to a public store's private endpoint once it is ready", ctx do
    public =
      Map.merge(ctx.config, %{
        "access" => "public",
        "endpoint" => "https://s3.example.com",
        "region" => "us-east-1",
        "private_endpoint" => "http://rustfs-s3.rustfs.svc.cluster.local:9000"
      })

    stub(Environment, :shard_storage_targets, fn -> %{"rustfs-v1" => public} end)

    expect(Storage, :available?, fn %S3Target{id: "rustfs-v1", config: %{host: host}} ->
      assert host == "rustfs-s3.rustfs.svc.cluster.local"
      true
    end)

    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == "rustfs-v1"

    # Never through the public host, and not before the store is ready.
    reject(&Storage.available?/1)

    for config <- [Map.delete(public, "private_endpoint"), %{public | "private_network_ready" => false}] do
      stub(Environment, :shard_storage_targets, fn -> %{"rustfs-v1" => config} end)
      assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == ""
    end
  end

  test "a Mac places plans in its own site's store and reaches it through each site's entrance", ctx do
    larch = %{
      "access" => "private",
      "site" => "larch",
      "enabled" => true,
      "endpoint" => "http://rustfs-larch-s3.rustfs-larch.svc.cluster.local:9000",
      "region" => "us-east-1",
      "bucket" => "shards",
      "access_key_id" => "larch-key",
      "secret_access_key" => "larch-secret",
      "runner_endpoints" => %{"larch" => "https://s3-larch.example.com", "ber1" => "https://s3-larch-ber1.example.com"}
    }

    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => ctx.config, "larch-v1" => larch} end)
    xcode = %Project{build_system: :xcode}
    at_larch = CacheGrant.mint(42, site: "larch", platform: :macos)
    at_ber1 = CacheGrant.mint(42, site: "ber1", platform: :macos)

    expect(Storage, :available?, fn %S3Target{id: "larch-v1", config: %{host: host}} ->
      assert host == "rustfs-larch-s3.rustfs-larch.svc.cluster.local"
      true
    end)

    assert ShardStorage.select(xcode, ctx.account, at_larch) == "larch-v1"

    # Placement stays at the store's own site unless placement_sites lists the
    # other one, whose Macs then place through their own entrance. Linux never does.
    stub(Storage, :available?, fn target -> flunk("probed #{inspect(target.id)}") end)
    assert ShardStorage.select(xcode, ctx.account, at_ber1) == ""

    assert Enum.sort_by(ShardStorage.placement_tags(), & &1.store) == [
             %{store: "gra-v1", platform: "linux", site: "gra"},
             %{store: "larch-v1", platform: "macos", site: "larch"}
           ]

    both = Map.put(larch, "placement_sites", ["larch", "ber1"])
    stub(Environment, :shard_storage_targets, fn -> %{"larch-v1" => both} end)

    expect(Storage, :available?, fn %S3Target{id: "larch-v1", presign_config: %{host: "s3-larch-ber1.example.com"}} ->
      true
    end)

    assert ShardStorage.select(xcode, ctx.account, at_ber1) == "larch-v1"
    assert ShardStorage.select(ctx.project, ctx.account, CacheGrant.mint(42, site: "ber1", platform: :linux)) == ""

    assert Enum.sort_by(ShardStorage.placement_tags(), & &1.site) == [
             %{store: "larch-v1", platform: "macos", site: "ber1"},
             %{store: "larch-v1", platform: "macos", site: "larch"}
           ]

    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => ctx.config, "larch-v1" => larch} end)

    plan = %ShardPlan{storage_target: "larch-v1"}
    key = "42/1/shards/plan/shared.aar"

    for {grant, host} <- [{at_larch, "s3-larch.example.com"}, {at_ber1, "s3-larch-ber1.example.com"}] do
      assert {:ok, %S3Target{config: config} = target} = ShardStorage.resolve_for_request(plan, ctx.account, grant)
      assert config.host == "rustfs-larch-s3.rustfs-larch.svc.cluster.local"
      url = URI.parse(Storage.multipart_generate_url(key, "upload", 1, target))
      assert {url.scheme, url.host, url.path} == {"https", host, "/shards/" <> key}
    end

    for grant <- [nil, ctx.grant, CacheGrant.mint(42, site: "other", platform: :macos)] do
      assert {:error, :shard_storage_unavailable} = ShardStorage.resolve_for_request(plan, ctx.account, grant)
    end

    # An entrance must be HTTPS: a Mac never gets a plaintext URL or a placement.
    plaintext = put_in(larch, ["runner_endpoints", "larch"], "http://s3-larch.example.com")
    stub(Environment, :shard_storage_targets, fn -> %{"larch-v1" => plaintext} end)
    assert ShardStorage.select(xcode, ctx.account, at_larch) == ""
    assert {:error, :shard_storage_unavailable} = ShardStorage.resolve_for_request(plan, ctx.account, at_larch)
  end

  test "fails back before persistence when readiness fails", ctx do
    expect(Storage, :available?, fn _ -> false end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == ""
  end

  test "unverified, foreign-account, macOS, and legacy grants never probe the store", ctx do
    reject(&Storage.available?/1)

    for grant <- [
          nil,
          "forged",
          CacheGrant.mint(43, site: "gra", platform: :linux),
          CacheGrant.mint(42, site: "gra", platform: :macos),
          CacheGrant.mint(42)
        ] do
      assert ShardStorage.select(ctx.project, ctx.account, grant) == ""
    end

    assert ShardStorage.select(%Project{build_system: :xcode}, ctx.account, ctx.grant) == ""
  end

  test "disabled flag and unconfirmed transport keep new plans on default storage", ctx do
    reject(&Storage.available?/1)
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> false end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == ""
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> true end)
    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => %{ctx.config | "private_network_ready" => false}} end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == ""
  end

  test "a persisted target survives disabled enrollment, uses path-style S3, and never rechecks readiness", ctx do
    reject(&Storage.available?/1)
    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => %{ctx.config | "enabled" => false}} end)
    assert {:ok, target} = ShardStorage.resolve(%ShardPlan{storage_target: "gra-v1"}, ctx.account)

    assert URI.parse(Storage.generate_download_url("42/1/shards/plan/bundle.zip", target)).host ==
             "shard-storage.kura.svc.cluster.local"

    assert URI.parse(Storage.generate_download_url("42/1/shards/plan/bundle.zip", target)).path ==
             "/shards/42/1/shards/plan/bundle.zip"
  end

  test "missing configuration never redirects a persisted plan", ctx do
    assert {:error, :shard_storage_unavailable} = ShardStorage.resolve(%ShardPlan{storage_target: "removed"}, ctx.account)
    assert {:ok, ctx.account} == ShardStorage.resolve(%ShardPlan{}, ctx.account)
  end

  test "local artifacts require the original site on consumers too", ctx do
    plan = %ShardPlan{storage_target: "gra-v1"}
    assert {:ok, %S3Target{}} = ShardStorage.resolve_for_request(plan, ctx.account, ctx.grant)

    for grant <- [nil, CacheGrant.mint(42, site: "other", platform: :linux)] do
      assert {:error, :shard_storage_unavailable} = ShardStorage.resolve_for_request(plan, ctx.account, grant)
    end
  end

  test "custom account storage remains authoritative for new plans", ctx do
    reject(&Storage.available?/1)
    account = %{ctx.account | s3_bucket_name: "custom", s3_access_key_id: "key", s3_secret_access_key: "secret"}
    assert ShardStorage.select(ctx.project, account, ctx.grant) == ""
    assert {:ok, ^account} = ShardStorage.resolve(%ShardPlan{}, account)
  end

  test "public targets require enrollment and HTTPS but no runner grant", ctx do
    public =
      Map.merge(ctx.config, %{"access" => "public", "endpoint" => "https://shards.example.com", "region" => "us-east-1"})

    stub(Environment, :shard_storage_targets, fn -> %{"public-v1" => public} end)
    project = %Project{build_system: :xcode}
    assert ShardStorage.select(project, ctx.account, nil, true) == ""
    stub(FeatureFlags, :public_shard_storage_enabled?, fn _ -> true end)
    stub(Storage, :available?, fn _ -> true end)

    for system <- [:xcode, :mix, :cargo] do
      assert ShardStorage.select(%Project{build_system: system}, ctx.account, nil, true) == "public-v1"
    end

    assert ShardStorage.select(project, ctx.account, nil) == ""

    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => ctx.config, "public-v1" => public} end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == "gra-v1"
    assert ShardStorage.select(ctx.project, ctx.account, nil, true) == "public-v1"

    stub(Storage, :available?, fn _ -> false end)
    assert ShardStorage.select(project, ctx.account, nil, true) == ""
    stub(Storage, :available?, fn _ -> true end)

    account = %{ctx.account | s3_bucket_name: "custom", s3_access_key_id: "key", s3_secret_access_key: "secret"}
    assert ShardStorage.select(project, account, nil, true) == ""

    for config <- [
          Map.put(public, "endpoint", "http://shards.example.com"),
          Map.delete(public, "region"),
          Map.put(public, "enabled", false)
        ] do
      stub(Environment, :shard_storage_targets, fn -> %{"public-v1" => config} end)
      assert ShardStorage.select(project, ctx.account, nil, true) == ""
    end
  end

  test "public plans retain identity across public and verified private requests after enrollment stops", ctx do
    config =
      Map.merge(ctx.config, %{
        "access" => "public",
        "endpoint" => "https://shards.example.com",
        "region" => "us-east-1",
        "private_endpoint" => "http://shards.internal:8080",
        "enabled" => false
      })

    stub(Environment, :shard_storage_targets, fn -> %{"public-v1" => config} end)
    plan = %ShardPlan{storage_target: "public-v1"}
    key = "42/1/shards/plan/shared.aar"

    for grant <- [
          nil,
          "forged",
          CacheGrant.mint(43, site: "gra", platform: :linux),
          CacheGrant.mint(42, site: "gra", platform: :macos),
          CacheGrant.mint(42, site: "other", platform: :linux)
        ] do
      assert {:ok, %S3Target{id: "public-v1"} = target} = ShardStorage.resolve_for_request(plan, ctx.account, grant)
      assert URI.parse(Storage.generate_download_url(key, target)).host == "shards.example.com"
    end

    assert {:ok, %S3Target{id: "public-v1"} = target} = ShardStorage.resolve_for_request(plan, ctx.account, ctx.grant)
    assert URI.parse(Storage.generate_download_url(key, target)).host == "shards.internal"
    assert {:ok, cleanup_target} = ShardStorage.resolve(plan, ctx.account)
    assert cleanup_target.bucket == target.bucket
    assert URI.parse(Storage.generate_download_url(key, cleanup_target)).host == "shards.example.com"

    stub(Environment, :shard_storage_targets, fn -> %{"public-v1" => %{config | "private_network_ready" => false}} end)
    assert {:ok, target} = ShardStorage.resolve_for_request(plan, ctx.account, ctx.grant)
    assert URI.parse(Storage.generate_download_url(key, target)).host == "shards.example.com"
  end
end
