defmodule Tuist.Ops.FeatureFlags do
  @moduledoc """
  Audited, revision-checked control of the existing FunWithFlags gates.
  Reads bypass the evaluation cache. Writes publish only after commit.
  """

  import Ecto.Query

  alias FunWithFlags.Gate
  alias FunWithFlags.Store
  alias FunWithFlags.Store.Persistent.Ecto, as: Persistence
  alias FunWithFlags.Store.Persistent.Ecto.Record
  alias FunWithFlags.Store.Serializer.Ecto, as: Serializer
  alias Tuist.Accounts.Account
  alias Tuist.Ops.FeatureFlagChange
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @catalog [
    {:immutable_shard_reports, "account", "Opt-in immutable shard plans; coverage-enabled accounts remain excluded."},
    {:kura_positive_fence, "account",
     "Opt-in managed positive-fence serving authority. Activation is sticky; disabling cannot restore legacy serving."},
    {:kura_placement_served_signal, "account", "Opt-in placement using served-region signals."},
    {:kura_stable_hostname, "account", "Stable cache hostname opt-in; canary enables automatically."},
    {:runners, "account", "Managed runners opt-in on canary/production; enabled elsewhere."},
    {:runner_site_cache, "account", "Opt-in site-local runner caches."},
    {:runner_site, "account", "Opt-in site runners; staging/canary enable automatically."},
    {:xcode_coverage, "account", "Coverage opt-in on canary/production; enabled elsewhere."},
    {:kura_account_endpoint_migration, "account",
     "Opt-in account endpoint migration. Disabling freezes deployed routing, rather than reverting it."},
    {:kura_account_rename, "account",
     "Account renaming opt-in on canary/production when Kura deployments or self-hosted clients exist; allowed otherwise."},
    {:qa_billing_enabled, "account", "Opt-in QA usage billing."},
    {:build_entities, "project", "Opt-in build inventories; build_entities_kill_switch overrides enrollment."},
    {:build_entities_kill_switch, "global", "Enabling stops build inventories for every project."},
    {:kura_rollout_orchestration_kill_switch, "global", "Enabling stops Kura rollout orchestration."},
    {:turnstile_kill_switch, "global", "Enabling disables Turnstile; environment configuration still applies."},
    {:public_page_challenge_kill_switch, "global",
     "Enabling disables public-page challenges; environment configuration still applies."},
    {:runner_pod_reconciliation_paused, "global", "Enabling pauses runner pod reconciliation."}
  ]

  @fields ~w(operation scope account_id project_id percentage expected_revision reason change_id actor interface)

  def list do
    {:ok, %{flags: snapshots(@catalog)}}
  end

  def get(name) do
    with {:ok, entry} <- entry(name), do: {:ok, snapshot(entry)}
  end

  def update(name, params, principal) do
    with {:ok, entry} <- entry(name),
         :ok <- validate_request(params) do
      result =
        Repo.transaction(fn ->
          # Flag writes are rare. This also serializes the legacy ops UI's
          # ordinary row writes, including insertion of previously absent gates.
          Repo.query!("SET LOCAL lock_timeout = '5s'")
          # Match the adapter's lock order: its percentage read-modify-write
          # starts with this advisory lock, before acquiring any table write lock.
          Repo.query!(
            "SELECT pg_advisory_xact_lock(hashtext('fun_with_flags_percentage_gate_upsert'), hashtext($1))",
            [Atom.to_string(elem(entry, 0))]
          )

          Repo.query!("LOCK TABLE feature_flags IN SHARE ROW EXCLUSIVE MODE")
          apply_change(entry, params, principal)
        end)

      case result do
        {:ok, flag} ->
          # Reload from committed storage, not the transaction's snapshot: a
          # later writer may already have committed while this caller resumed.
          Store.reload(elem(entry, 0))
          FunWithFlags.Config.notifications_adapter().publish_change(elem(entry, 0))
          {:ok, flag}

        error ->
          error
      end
    end
  end

  defp apply_change({name, _, _} = entry, params, principal) do
    flag_name = Atom.to_string(name)

    case Repo.get_by(FeatureFlagChange, change_id: params["change_id"]) do
      %FeatureFlagChange{flag_name: ^flag_name, request: request, after: after_state} ->
        if request == params, do: after_state, else: Repo.rollback(:change_id_conflict)

      %FeatureFlagChange{} ->
        Repo.rollback(:change_id_conflict)

      nil ->
        gate =
          case gate(entry, params) do
            {:ok, gate} -> gate
            {:error, reason} -> Repo.rollback(reason)
          end

        before_state = snapshot(entry)

        if before_state.revision != params["expected_revision"], do: Repo.rollback(:stale_revision)

        persist(name, params["operation"], gate)

        change =
          Repo.insert!(%FeatureFlagChange{
            change_id: params["change_id"],
            flag_name: Atom.to_string(name),
            request: params,
            principal: principal,
            before: json_map(before_state),
            after: %{}
          })

        after_state = snapshot(entry)
        change |> Ecto.Changeset.change(after: json_map(after_state)) |> Repo.update!()
        after_state
    end
  end

  defp persist(name, "clear", :all), do: unwrap(Persistence.delete(name))
  defp persist(name, "clear", gate), do: unwrap(Persistence.delete(name, gate))
  defp persist(name, _operation, gate), do: unwrap(Persistence.put(name, gate))

  defp unwrap({:ok, flag}), do: flag
  defp unwrap({:error, _reason}), do: Repo.rollback(:persistence_failed)

  defp snapshot(entry), do: entry |> List.wrap() |> snapshots() |> hd()

  defp snapshots(entries) do
    names = Enum.map(entries, fn {name, _, _} -> Atom.to_string(name) end)
    revisions = from(c in FeatureFlagChange, group_by: c.flag_name, select: %{flag_name: c.flag_name, version: max(c.id)})

    # Read gates and revisions in one database snapshot, including flags whose
    # last operation cleared every gate. Listing does not issue per-flag reads.
    rows =
      from(n in fragment("(SELECT unnest(?::text[]) AS flag_name)", ^names),
        left_join: r in Record,
        on: r.flag_name == field(n, :flag_name),
        left_join: c in subquery(revisions),
        on: c.flag_name == field(n, :flag_name),
        select: {field(n, :flag_name), r, c.version}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0))

    Enum.map(entries, fn {name, actor_type, description} ->
      records = Map.fetch!(rows, Atom.to_string(name))
      {_, _, last_change} = hd(records)

      flag =
        Serializer.deserialize_flag(
          name,
          Enum.flat_map(records, fn {_, record, _} -> if record, do: [record], else: [] end)
        )

      gates =
        flag.gates
        |> Enum.map(fn gate ->
          %{
            type: Atom.to_string(gate.type),
            target: if(is_nil(gate.for), do: nil, else: to_string(gate.for)),
            enabled: gate.enabled
          }
        end)
        |> Enum.sort_by(&{&1.type, &1.target})

      revision = :sha256 |> :crypto.hash(:erlang.term_to_binary({gates, last_change})) |> Base.encode16(case: :lower)
      %{name: Atom.to_string(name), actor_type: actor_type, description: description, gates: gates, revision: revision}
    end)
  end

  defp entry(name) when is_binary(name) do
    case Enum.find(@catalog, fn {atom, _, _} -> Atom.to_string(atom) == name end) do
      nil -> {:error, :unknown_flag}
      entry -> {:ok, entry}
    end
  end

  defp entry(_), do: {:error, :unknown_flag}

  defp validate_request(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @fields)),
         true <- params["operation"] in ~w(enable disable clear),
         true <- params["interface"] in ~w(mcp worker slack api),
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

  defp gate(_entry, %{"scope" => "all", "operation" => "clear"} = params) do
    if target_fields(params) == %{}, do: {:ok, :all}, else: {:error, :invalid_target}
  end

  defp gate(_entry, %{"scope" => "global"} = params) do
    if target_fields(params) == %{},
      do: {:ok, Gate.new(:boolean, params["operation"] == "enable")},
      else: {:error, :invalid_target}
  end

  defp gate({_, "account", _}, %{"scope" => "account", "account_id" => id} = params) when is_integer(id) and id > 0 do
    if target_fields(params) == %{"account_id" => id} and Repo.exists?(from(a in Account, where: a.id == ^id)),
      do: {:ok, Gate.new(:actor, %Account{id: id}, params["operation"] == "enable")},
      else: {:error, :invalid_target}
  end

  defp gate({_, "project", _}, %{"scope" => "project", "project_id" => id} = params) when is_integer(id) and id > 0 do
    if target_fields(params) == %{"project_id" => id} and Repo.exists?(from(p in Project, where: p.id == ^id)),
      do: {:ok, Gate.new(:actor, %Project{id: id}, params["operation"] == "enable")},
      else: {:error, :invalid_target}
  end

  defp gate({_, actor_type, _}, %{"scope" => "percentage", "operation" => "enable", "percentage" => percentage} = params)
       when actor_type in ["account", "project"] and is_number(percentage) and percentage > 0 and percentage < 100 do
    if target_fields(params) == %{"percentage" => percentage},
      do: {:ok, Gate.new(:percentage_of_actors, percentage / 100)},
      else: {:error, :invalid_target}
  end

  defp gate({_, actor_type, _}, %{"scope" => "percentage", "operation" => "clear"} = params)
       when actor_type in ["account", "project"] do
    if target_fields(params) == %{},
      do: {:ok, Gate.new(:percentage_of_actors, 0.5)},
      else: {:error, :invalid_target}
  end

  defp gate(_entry, _params), do: {:error, :invalid_target}
  defp target_fields(params), do: Map.take(params, ~w(account_id project_id percentage))
  defp json_map(value), do: value |> JSON.encode!() |> JSON.decode!()
end
