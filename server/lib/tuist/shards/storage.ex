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

  def routable?(project), do: project.build_system in [:mix, :cargo]

  def select(project, account, grant) do
    with true <- routable?(project),
         false <- Account.custom_s3_storage_configured?(account),
         true <- FeatureFlags.runner_shard_storage_enabled?(account),
         {:ok, site} <- CacheGrant.linux_site(grant, account.id) do
      Environment.shard_storage_targets()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.find_value("", fn {id, config} ->
        with true <- is_map(config),
             true <- config["enabled"] == true and config["private_network_ready"] == true,
             true <- config["site"] == site,
             {:ok, target} <- target(id, config),
             true <- Storage.available?(target) do
          id
        else
          _ -> nil
        end
      end)
    else
      _ -> ""
    end
  end

  def resolve(%{storage_target: id}, account) when id in [nil, ""], do: {:ok, account}

  def resolve(%{storage_target: id}, _account) do
    case Map.fetch(Environment.shard_storage_targets(), id) do
      {:ok, config} -> target(id, config)
      :error -> {:error, :shard_storage_unavailable}
    end
  end

  # Consumers must also be on enrolled nodes at this site. Otherwise a plan
  # created on a private node could hand a plain-HTTP URL to a WAN-only runner.
  # Cleanup uses resolve/2 and remains independent of short-lived job grants.
  def resolve_for_request(%{storage_target: id} = plan, account, grant) do
    with {:ok, actor} <- resolve(plan, account) do
      if id in [nil, ""] do
        {:ok, actor}
      else
        site = Environment.shard_storage_targets()[id]["site"]

        case CacheGrant.linux_site(grant, account.id) do
          {:ok, ^site} -> {:ok, actor}
          _ -> {:error, :shard_storage_unavailable}
        end
      end
    end
  end

  defp target(id, config) do
    with %{"endpoint" => endpoint, "bucket" => bucket, "access_key_id" => key, "secret_access_key" => secret} <- config,
         true <- Enum.all?([endpoint, bucket, key, secret], &(is_binary(&1) and &1 != "")),
         %URI{scheme: scheme, host: host, port: port, path: path, userinfo: nil, query: nil, fragment: nil} <-
           URI.parse(endpoint),
         true <- scheme in ["http", "https"] and is_binary(host) and path in [nil, "", "/"] do
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
