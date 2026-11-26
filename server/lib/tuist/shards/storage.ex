defmodule Tuist.Shards.Storage do
  @moduledoc """
  Selects storage once, when a plan is created. Disabling enrollment or losing
  readiness never redirects an existing plan to a different bucket.
  """
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Runners.CacheGrant
  alias Tuist.Storage
  alias Tuist.Storage.S3Target

  def routable?(project), do: project.build_system in [:xcode, :mix, :cargo]

  # `public_storage?` is false unless the uploading client spreads multipart parts
  # over separate connections; older CLIs multiplex every part onto one HTTP/2
  # connection to a public store and upload several times slower than to Tigris.
  def select(project, account, grant, public_storage? \\ false) do
    with true <- routable?(project),
         false <- Account.custom_s3_storage_configured?(account) do
      select_private(project, account, grant) || (public_storage? && select_public(account)) || ""
    else
      _ -> ""
    end
  end

  defp select_private(project, account, grant) do
    with true <- FeatureFlags.runner_shard_storage_enabled?(account),
         {:ok, platform, site} <- CacheGrant.runner_site(grant, account.id),
         true <- platform == :macos or project.build_system in [:mix, :cargo] do
      Environment.shard_storage_targets()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.find_value(fn {id, config} ->
        with true <- is_map(config),
             true <- config["enabled"] == true and site in placement_sites(platform, config),
             {:ok, target} <- placement_target(platform, id, config, site),
             true <- Storage.available?(target) do
          id
        else
          _ -> nil
        end
      end)
    else
      _ -> nil
    end
  end

  # A Linux runner reaches its site's store over the private network once the
  # provider attests its routes; a Mac only through its site's gateway entrance.
  defp placement_target(:linux, id, config, _site) do
    if (Map.get(config, "access", "private") == "private" or is_binary(config["private_endpoint"])) and
         config["private_network_ready"] == true,
       do: in_cluster_target(id, config),
       else: {:error, :shard_storage_unavailable}
  end

  defp placement_target(:macos, id, config, site), do: runner_entrance_target(id, config, site)

  # A Linux runner places only at the store's own site. A Mac may also place
  # from each site in `placement_sites`, through that site's entrance.
  defp placement_sites(:linux, config), do: [config["site"]]

  defp placement_sites(:macos, config) do
    case config["placement_sites"] do
      sites when is_list(sites) -> sites
      _ -> [config["site"]]
    end
  end

  @doc """
  The metric tags of every private placement the configuration allows, so the
  plans counter publishes each series at zero before its first plan.
  """
  def placement_tags do
    for {id, %{"enabled" => true} = config} <- Environment.shard_storage_targets(),
        platform <- [:linux, :macos],
        site <- placement_sites(platform, config),
        is_binary(site),
        match?({:ok, _}, placement_target(platform, id, config, site)) do
      %{store: id, platform: Atom.to_string(platform), site: site}
    end
  end

  defp select_public(account) do
    if FeatureFlags.public_shard_storage_enabled?(account) do
      Environment.shard_storage_targets()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.find_value(fn {id, config} ->
        with %{"access" => "public", "enabled" => true} <- config,
             {:ok, target} <- s3_target(id, config),
             true <- Storage.available?(target) do
          id
        else
          _ -> nil
        end
      end)
    end
  end

  @doc """
  Metric tags for a plan's store and the verified runner placing or uploading
  it: `store` is the target ID or `default`, and `platform` and `site` are
  `none` without a valid runner grant. All bounded by configuration.
  """
  def telemetry_tags(storage_target, account, grant) do
    {platform, site} =
      case CacheGrant.runner_site(grant, account.id) do
        {:ok, platform, site} -> {Atom.to_string(platform), site}
        _ -> {"none", "none"}
      end

    %{store: if(storage_target in [nil, ""], do: "default", else: storage_target), platform: platform, site: site}
  end

  def resolve(%{storage_target: id}, account) when id in [nil, ""], do: {:ok, account}

  def resolve(%{storage_target: id}, _account) do
    case Map.fetch(Environment.shard_storage_targets(), id) do
      {:ok, config} -> s3_target(id, config)
      :error -> {:error, :shard_storage_unavailable}
    end
  end

  # Private targets still require the original site. Public targets may select
  # a same-store private endpoint only for a verified same-site Linux runner. A
  # Mac at a site the store publishes a gateway entrance for (`runner_endpoints`)
  # reaches it there, whichever site the plan was placed at.
  # Cleanup uses resolve/2 and remains independent of short-lived job grants.
  def resolve_for_request(%{storage_target: id} = plan, account, grant) do
    with {:ok, actor} <- resolve(plan, account) do
      if id in [nil, ""] do
        {:ok, actor}
      else
        resolve_target_for_request(id, Environment.shard_storage_targets()[id], actor, account, grant)
      end
    end
  end

  defp resolve_target_for_request(id, config, actor, account, grant) do
    site = config["site"]

    case {config["access"], CacheGrant.runner_site(grant, account.id)} do
      {access, {:ok, :macos, runner_site}} ->
        with {:error, _} <- runner_entrance_target(id, config, runner_site) do
          if access == "public", do: {:ok, actor}, else: {:error, :shard_storage_unavailable}
        end

      {"public", {:ok, :linux, ^site}} ->
        if config["private_network_ready"] == true, do: in_cluster_target(id, config), else: {:ok, actor}

      {"public", _} ->
        {:ok, actor}

      {_, {:ok, :linux, ^site}} ->
        {:ok, actor}

      _ ->
        {:error, :shard_storage_unavailable}
    end
  end

  # The server's own calls stay on the in-cluster endpoint; the URLs a Mac
  # follows are signed for its site's entrance, which must be HTTPS.
  defp runner_entrance_target(id, config, site) do
    with %{^site => endpoint} when is_binary(endpoint) <- config["runner_endpoints"],
         {:ok, target} <- in_cluster_target(id, config),
         {:ok, %S3Target{config: presign_config}} <-
           s3_target(id, Map.merge(config, %{"endpoint" => endpoint, "access" => "public"})) do
      {:ok, %{target | presign_config: presign_config}}
    else
      _ -> {:error, :shard_storage_unavailable}
    end
  end

  @doc """
  The S3 target for callers on the store's private network: a public store's
  `private_endpoint` when it publishes one, otherwise its only endpoint. The
  Actions cache and sandbox archive buckets are only reachable there, so their
  existing objects stay readable while new placements still wait for
  `private_network_ready`.
  """
  def in_cluster_target(id, %{"access" => "public", "private_endpoint" => endpoint} = config) when is_binary(endpoint) do
    s3_target(id, Map.merge(config, %{"endpoint" => endpoint, "access" => "private"}))
  end

  def in_cluster_target(id, config), do: s3_target(id, config)

  @doc """
  The S3 target a storage target configuration describes: its endpoint,
  `"bucket"` and key.
  """
  def s3_target(id, config) do
    with %{"endpoint" => endpoint, "bucket" => bucket, "access_key_id" => key, "secret_access_key" => secret} <- config,
         true <- Map.get(config, "access", "private") in ["private", "public"],
         true <- Enum.all?([endpoint, bucket, key, secret], &(is_binary(&1) and &1 != "")),
         %URI{scheme: scheme, host: host, port: port, path: path, userinfo: nil, query: nil, fragment: nil} <-
           URI.parse(endpoint),
         true <- scheme in ["http", "https"] and is_binary(host) and path in [nil, "", "/"],
         true <-
           config["access"] != "public" or (scheme == "https" and is_binary(config["region"]) and config["region"] != "") do
      aws_config =
        ExAws.Config.new(:s3,
          scheme: scheme <> "://",
          host: host,
          port: port,
          region: config["region"] || "garage",
          virtual_host: false,
          bucket_as_host: false,
          access_key_id: key,
          secret_access_key: secret
        )

      {:ok, %S3Target{id: id, config: aws_config, bucket: bucket}}
    else
      _ -> {:error, :shard_storage_unavailable}
    end
  end
end
