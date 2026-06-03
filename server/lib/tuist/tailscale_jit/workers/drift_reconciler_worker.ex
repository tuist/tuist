defmodule Tuist.TailscaleJIT.Workers.DriftReconcilerWorker do
  @moduledoc """
  Periodic reaper: lists actual members of every break-glass group
  from Tailscale and removes anyone who isn't backed by an
  `:active` Elevation row. Catches "ACL POST succeeded but DB
  write didn't," out-of-band manual edits in the Tailscale admin
  console, and any drift the RevertWorker couldn't recover from.

  Runs every 5 minutes from `Tuist.Oban.RuntimeConfig`. Cheap (one
  GET + one POST when drift is detected, no-op otherwise).
  """

  use Oban.Worker,
    queue: :tailscale_jit,
    max_attempts: 3

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.TailscaleJIT.ACLMutation
  alias Tuist.TailscaleJIT.Elevation
  alias Tuist.TailscaleJIT.TailscaleClient

  require Logger

  @managed_groups [
    "group:tuist-staging-write",
    "group:tuist-canary-write",
    "group:tuist-prod-write"
  ]

  @impl Oban.Worker
  def perform(_job) do
    if is_nil(Tuist.Environment.tailscale_jit_client_id()) do
      # Cron fires on every prod-like env (the runtime config has
      # one entry list), but only prod has the OAuth client wired
      # in. No-op everywhere else.
      :ok
    else
      case TailscaleClient.get_acl() do
        {:ok, doc, _etag} ->
          reconcile(doc)

        {:error, reason} ->
          Logger.warning("tailscale_jit: drift reconciler GET failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp reconcile(doc) do
    active = active_membership()
    drift = compute_drift(doc, active)

    if drift == [] do
      :ok
    else
      Logger.warning("tailscale_jit: drift detected: #{inspect(drift)}")
      apply_drift_removals(drift)
    end
  end

  defp active_membership do
    from(e in Elevation,
      where: e.status == "active",
      select: {e.target_group, e.requester_email}
    )
    |> Repo.all()
    |> Enum.group_by(fn {group, _} -> group end, fn {_, email} -> email end)
  end

  defp compute_drift(doc, active_by_group) do
    @managed_groups
    |> Enum.flat_map(fn group ->
      case ACLMutation.list_members(doc, group) do
        {:ok, members} ->
          allowed = Map.get(active_by_group, group, [])
          members |> Enum.reject(&(&1 in allowed)) |> Enum.map(&{group, &1})

        {:error, _} ->
          []
      end
    end)
  end

  defp apply_drift_removals(drift) do
    result =
      TailscaleClient.update_acl(fn doc ->
        Enum.reduce_while(drift, {:ok, doc}, fn {group, email}, {:ok, acc} ->
          case ACLMutation.remove_member(acc, group, email) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end)

    case result do
      {:ok, _} ->
        Logger.info("tailscale_jit: drift reaped (#{length(drift)} entries)")
        :ok

      {:error, reason} ->
        Logger.error("tailscale_jit: drift reap failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def managed_groups, do: @managed_groups
end
