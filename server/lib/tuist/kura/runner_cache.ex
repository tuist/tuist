defmodule Tuist.Kura.RunnerCache do
  @moduledoc """
  Keeps a private runner-cache Kura node provisioned for exactly the
  accounts that have runners-as-a-service turned on.

  The identity rule is simple and converges both directions every tick:

    * an account with `runner_max_concurrent > 0` should have exactly one
      non-destroyed Kura server in the active runner-cache region, and
    * an account with runners off (`runner_max_concurrent <= 0`) should
      have none.

  This runs inside `Tuist.Kura.Reconciler`'s tick rather than on its own
  cron, so it shares the same cadence and self-heals after a BEAM
  restart: enabling runners provisions the node on the next tick;
  disabling them tears it down. It is a no-op unless a private region is
  available in this runtime (via `TUIST_KURA_AVAILABLE_REGIONS`) and a
  Kura runtime image tag is configured, so non-managed and not-yet-wired
  environments stay inert.

  Provisioning the node does not, by itself, route any traffic to it —
  `Tuist.Kura.runner_cache_endpoint_url/1` only returns a URL once the
  node is `:active`, and runner dispatch resolves that lazily.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Kura
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @doc """
  Converges runner-cache nodes with runner enablement. Safe to call on
  every reconciler tick; returns `:ok`.
  """
  def reconcile do
    case runner_cache_region() do
      nil -> :ok
      %Regions{id: region_id} -> reconcile_region(region_id)
    end
  end

  defp reconcile_region(region_id) do
    # Tear down first so an account that flips runners off frees its node
    # even when no image tag is configured to provision new ones.
    Enum.each(nodes_to_tear_down(region_id), &tear_down/1)

    case image_tag() do
      nil -> :ok
      image_tag -> Enum.each(accounts_needing_node(region_id), &provision(&1, region_id, image_tag))
    end

    :ok
  end

  # The first private (runner-cache) region available in this runtime,
  # or nil. `available/0` is env-gated, so this stays nil until a
  # private region is wired into `TUIST_KURA_AVAILABLE_REGIONS`.
  defp runner_cache_region do
    Enum.find(Regions.available(), &Regions.private?/1)
  end

  defp image_tag do
    case Tuist.Environment.kura_runtime_image_tag() do
      tag when is_binary(tag) ->
        case String.trim(tag) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp accounts_needing_node(region_id) do
    server_exists =
      from(s in Server,
        where:
          s.account_id == parent_as(:account).id and s.region == ^region_id and
            s.status != :destroyed,
        select: 1
      )

    Repo.all(
      from(a in Account,
        as: :account,
        where: a.runner_max_concurrent > 0,
        where: not exists(server_exists),
        select: a.id
      )
    )
  end

  defp nodes_to_tear_down(region_id) do
    Repo.all(
      from(s in Server,
        join: a in assoc(s, :account),
        where: s.region == ^region_id,
        where: s.status not in [:destroying, :destroyed],
        where: a.runner_max_concurrent <= 0,
        select: s
      )
    )
  end

  defp provision(account_id, region_id, image_tag) do
    case Kura.create_server(%{account_id: account_id, region: region_id, image_tag: image_tag}) do
      {:ok, _server} ->
        Logger.info("[Kura.RunnerCache] provisioned runner-cache node for account #{account_id} in #{region_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Kura.RunnerCache] could not provision runner-cache node for account #{account_id} in #{region_id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp tear_down(%Server{} = server) do
    case Kura.destroy_server(server) do
      {:ok, _server} ->
        Logger.info("[Kura.RunnerCache] tearing down runner-cache node #{server.id} (runners disabled)")
        :ok

      {:error, reason} ->
        Logger.warning("[Kura.RunnerCache] could not tear down runner-cache node #{server.id}: #{inspect(reason)}")

        :ok
    end
  end
end
