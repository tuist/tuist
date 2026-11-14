defmodule Tuist.Ops.RunnerConcurrencyLimits do
  @moduledoc """
  Audited, revision-checked control of an account's runner concurrency
  limits for Atlas, the counterpart of the ops dashboard form.

  Like `Tuist.Ops.FeatureFlags`, a write names the revision it read, a
  reason and a change UUID; the request, workload principal and
  before/after state commit together with the new limits.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Ops.RunnerConcurrencyLimitChange
  alias Tuist.Repo
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.ConcurrencyLimit

  @platforms ~w(linux macos)
  @fields ~w(platform vcpus memory_gb expected_revision reason change_id actor interface)
  # `runner_concurrency_limits.vcpus` and `.memory_gb` are PostgreSQL integers.
  @max_resource 2_147_483_647

  def get(account_id) do
    with {:ok, id} <- account_id(account_id),
         {:ok, account} <- fetch_account(id) do
      snapshot(account)
    end
  end

  def update(account_id, params, principal) do
    with {:ok, id} <- account_id(account_id),
         :ok <- validate_request(params) do
      Repo.transaction(fn ->
        account =
          case fetch_account(id) do
            {:ok, account} -> account
            {:error, reason} -> Repo.rollback(reason)
          end

        # The same row locks the ops form takes, so a concurrent dashboard
        # edit either lands before the revision check or waits for this one.
        locked =
          ConcurrencyLimit
          |> where([limit], limit.account_id == ^account.id)
          |> order_by([limit], limit.platform)
          |> lock("FOR UPDATE")
          |> Repo.all()

        case Repo.get_by(RunnerConcurrencyLimitChange, change_id: params["change_id"]) do
          nil -> apply_change(account, locked, params, principal)
          change -> replay(change, id, params)
        end
      end)
    end
  end

  # An identical retry returns the recorded result, even after later changes.
  defp replay(
         %RunnerConcurrencyLimitChange{account_id: account_id, request: params, after: after_state},
         account_id,
         params
       ), do: after_state

  defp replay(_change, _account_id, _params), do: Repo.rollback(:change_id_conflict)

  defp apply_change(account, locked, params, principal) do
    before_state = unwrap(snapshot(account))
    if before_state.revision != params["expected_revision"], do: Repo.rollback(:stale_revision)

    # The ops form writes both platforms at once; keep the other platform's
    # current values so only the requested one changes.
    attrs =
      Map.new(locked, fn limit ->
        resources =
          if Atom.to_string(limit.platform) == params["platform"],
            do: %{vcpus: params["vcpus"], memory_gb: params["memory_gb"]},
            else: Concurrency.limit_resources(limit)

        {limit.platform, resources}
      end)

    case Concurrency.update_limits(account, %{
           runner_linux_vcpus_limit: attrs.linux.vcpus,
           runner_linux_memory_gb_limit: attrs.linux.memory_gb,
           runner_macos_vcpus_limit: attrs.macos.vcpus,
           runner_macos_memory_gb_limit: attrs.macos.memory_gb
         }) do
      {:ok, _account} -> :ok
      {:error, _reason} -> Repo.rollback(:invalid_request)
    end

    change =
      %{
        change_id: params["change_id"],
        account_id: account.id,
        request: params,
        principal: principal,
        before: json_map(before_state),
        after: %{}
      }
      |> RunnerConcurrencyLimitChange.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, change} -> change
        {:error, _changeset} -> Repo.rollback(:change_id_conflict)
      end

    after_state = json_map(unwrap(snapshot(account)))
    change |> Ecto.Changeset.change(after: after_state) |> Repo.update!()
    after_state
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: Repo.rollback(reason)

  defp snapshot(%Account{} = account) do
    limits = Repo.all(from(limit in ConcurrencyLimit, where: limit.account_id == ^account.id))

    # The database trigger creates both rows with every account; a missing
    # one means no runner job for that platform can be admitted.
    if length(limits) == length(@platforms) do
      usage = Concurrency.usage_by_platform(account.id)
      defaults = Concurrency.default_limits()

      last_change =
        Repo.one(
          from(change in RunnerConcurrencyLimitChange,
            where: change.account_id == ^account.id,
            select: max(change.id)
          )
        )

      limits = Enum.sort_by(limits, & &1.platform)

      # `updated_at` also changes on ops dashboard writes, which record no change row.
      # Hash plain values only: the encoding of a struct such as DateTime can
      # differ between replicas, which made the revision depend on the pod.
      revision =
        limits
        |> Enum.map(&{Atom.to_string(&1.platform), &1.vcpus, &1.memory_gb, DateTime.to_iso8601(&1.updated_at)})
        |> then(&{&1, last_change})
        |> :erlang.term_to_binary()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      {:ok,
       %{
         account_id: account.id,
         account_handle: account.name,
         revision: revision,
         limits:
           Enum.map(limits, fn limit ->
             %{
               platform: Atom.to_string(limit.platform),
               vcpus: limit.vcpus,
               memory_gb: limit.memory_gb,
               used_vcpus: usage[limit.platform].vcpus,
               used_memory_gb: usage[limit.platform].memory_gb,
               default_vcpus: defaults[limit.platform].vcpus,
               default_memory_gb: defaults[limit.platform].memory_gb
             }
           end)
       }}
    else
      {:error, :runner_concurrency_limits_missing}
    end
  end

  defp fetch_account(id) do
    case Repo.get(Account, id) do
      nil -> {:error, :resource_not_found}
      account -> {:ok, account}
    end
  end

  defp account_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: {:ok, id}

  defp account_id(id) when is_binary(id) and byte_size(id) in 1..19 do
    case Integer.parse(id) do
      {id, ""} -> account_id(id)
      _ -> {:error, :invalid_target}
    end
  end

  defp account_id(_id), do: {:error, :invalid_target}

  defp validate_request(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @fields)),
         true <- params["platform"] in @platforms,
         true <- resource?(params["vcpus"]) and resource?(params["memory_gb"]),
         true <- params["interface"] in ~w(mcp worker api),
         true <- is_binary(params["reason"]) and byte_size(params["reason"]) in 1..1000,
         true <- String.trim(params["reason"]) != "",
         true <- is_binary(params["expected_revision"]) and byte_size(params["expected_revision"]) == 64,
         {:ok, _} <- Ecto.UUID.cast(params["change_id"]),
         %{"id" => id, "email" => email} = actor when map_size(actor) == 2 <- params["actor"],
         {:ok, _} <- Ecto.UUID.cast(id),
         true <- is_binary(email) and byte_size(email) in 1..320 do
      :ok
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate_request(_), do: {:error, :invalid_request}

  defp resource?(value), do: is_integer(value) and value > 0 and value <= @max_resource

  defp json_map(value), do: value |> JSON.encode!() |> JSON.decode!()
end
