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
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Kura.Identity
  alias Tuist.Observability
  alias Tuist.Ops.FeatureFlagChange
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @catalog [
    {:pulse, "account",
     "Opt-in organization Pulse dashboards and APIs; configured tenant ownership and membership still apply."},
    {:bazel_remote_execution, "account",
     "Opt-in Linux Bazel execution; configured capacity and project grants still apply."},
    {:immutable_shard_reports, "account",
     "Disabled in code until immutable shard plans support coverage and test selection; the toggle has no effect."},
    {:runner_shard_storage, "account",
     "Opt-in Linux Mix/Cargo plans and rack Mac plans to their runner site's store; existing plans keep their store."},
    {:public_shard_storage, "account",
     "Opt-in Xcode/Mix/Cargo plans to public shard storage; custom S3 and eligible private stores take priority. Existing plans keep their store."},
    {:kura_positive_fence, "account",
     "Opt-in managed positive-fence serving authority. Activation is sticky; disabling cannot restore legacy serving."},
    {:kura_placement_served_signal, "account", "Opt-in placement using served-region signals."},
    {:kura_thin_volumes, "account",
     "Opt-in thin encrypted Kura volumes in regions listed in TUIST_KURA_THIN_REGIONS; other regions ignore it."},
    {:kura_stable_hostname, "account", "Stable cache hostname opt-in; canary enables automatically."},
    {:runner_concurrency_growth_paused, "account",
     "Enabling pauses automatic runner concurrency growth, globally or for one account; existing limits are preserved."},
    {:runner_site_cache, "account", "Opt-in site-local runner caches."},
    {:runner_site_cache_pinned, "account",
     "Gives a site account its site-local runner cache without site cache traffic; capacity still applies."},
    {:runner_site_cache_excluded, "account",
     "Tears down an account's site-local runner caches; its jobs still run at the site."},
    {:runner_site, "account", "Opt-in site runners; staging/canary enable automatically."},
    {:runner_actions_cache, "account",
     "GitHub Actions cache served by Linux runner hosts; opt-in on production, enabled elsewhere."},
    {:test_impact_analysis, "account",
     "Coverage-based test selection opt-in on canary/production; enabled elsewhere. Needs coverage."},
    {:snapshots, "account", "Hosted snapshot testing opt-in on canary/production; enabled elsewhere."},
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

  # Flags outside the catalog, including ones a write creates, have no known
  # actor type or feature helper: their gates may target accounts or projects,
  # and evaluation reports only catalog flags. Names follow the legacy ops UI.
  @uncataloged_name ~r/\A\w{1,255}\z/
  @uncataloged_description "Not in the operator catalog: its gates are applied as written, by name, and it is not evaluated."

  @fields ~w(operation scope account_id project_id percentage expected_revision reason change_id actor interface)

  @evaluators %{
    pulse: {FeatureFlags, :pulse_enabled?},
    bazel_remote_execution: {FeatureFlags, :bazel_remote_execution_enabled?},
    immutable_shard_reports: {FeatureFlags, :immutable_shard_reports_enabled?},
    runner_shard_storage: {FeatureFlags, :runner_shard_storage_enabled?},
    public_shard_storage: {FeatureFlags, :public_shard_storage_enabled?},
    kura_positive_fence: {FeatureFlags, :kura_positive_fence_enabled?},
    kura_placement_served_signal: {FeatureFlags, :kura_placement_served_signal_enabled?},
    kura_thin_volumes: {FeatureFlags, :kura_thin_volumes_enabled?},
    kura_stable_hostname: {FeatureFlags, :kura_stable_hostname_enabled?},
    runner_concurrency_growth_paused: {FeatureFlags, :runner_concurrency_growth_enabled?},
    runner_site_cache: {FeatureFlags, :runner_site_cache_enabled?},
    runner_site_cache_pinned: {FeatureFlags, :runner_site_cache_pinned?},
    runner_site_cache_excluded: {FeatureFlags, :runner_site_cache_excluded?},
    runner_site: {FeatureFlags, :runner_site_enabled?},
    runner_actions_cache: {FeatureFlags, :runner_actions_cache_enabled?},
    test_impact_analysis: {FeatureFlags, :test_impact_analysis_account_enabled?},
    snapshots: {FeatureFlags, :snapshots_enabled?},
    kura_account_endpoint_migration: {Identity, :endpoint_migration_enabled?},
    kura_account_rename: {Identity, :rename_allowed?},
    build_entities: {FeatureFlags, :build_entities_enabled?},
    kura_rollout_orchestration_kill_switch: {FeatureFlags, :kura_rollout_orchestration_enabled?},
    turnstile_kill_switch: {FeatureFlags, :turnstile_enabled?},
    public_page_challenge_kill_switch: {FeatureFlags, :public_page_challenge_enabled?}
  }
  @effective_names %{
    runner_concurrency_growth_paused: :runner_concurrency_growth,
    kura_rollout_orchestration_kill_switch: :kura_rollout_orchestration,
    turnstile_kill_switch: :turnstile,
    public_page_challenge_kill_switch: :public_page_challenge
  }

  def list do
    cataloged = Enum.map(@catalog, fn {name, _, _} -> Atom.to_string(name) end)

    names =
      Repo.all(
        from(r in Record,
          where: r.flag_name not in ^cataloged,
          distinct: true,
          order_by: r.flag_name,
          select: r.flag_name
        )
      )

    uncataloged = for name <- names, {:ok, entry} <- [entry(name)], do: entry

    {:ok, %{flags: snapshots(@catalog ++ uncataloged)}}
  end

  def get(name) do
    with {:ok, entry} <- entry(name), do: {:ok, snapshot(entry)}
  end

  def evaluate(params) do
    with {:ok, {type, id}} <- evaluation_target(params),
         {:ok, {account, project}} <- resource(type, id) do
      selection = %{selected_account: account, selected_project: project}

      Observability.with_context(selection, fn ->
        entries = Enum.filter(@catalog, fn {_, actor_type, _} -> actor_type != "project" or not is_nil(project) end)
        names = Enum.map(entries, fn {name, _, _} -> Atom.to_string(name) end)
        actors = [account, project] |> Enum.reject(&is_nil/1) |> Enum.map(&FunWithFlags.Actor.id/1)

        # Separate indexed branches keep other tenants' actor overrides out of
        # the read, while one SQL statement gives every flag the same snapshot.
        shared = from(r in Record, where: r.flag_name in ^names and r.gate_type in ~w(boolean group percentage))
        scoped = from(r in Record, where: r.flag_name in ^names and r.gate_type == "actor" and r.target in ^actors)

        records =
          shared
          |> union_all(^scoped)
          |> Repo.all()
          |> Enum.group_by(& &1.flag_name)

        flags =
          Map.new(entries, fn {name, _, _} ->
            {name, Serializer.deserialize_flag(name, Map.get(records, Atom.to_string(name), []))}
          end)

        evaluations =
          Enum.map(entries, fn {name, actor_type, description} ->
            actor = evaluation_actor(actor_type, account, project)

            %{
              name: Atom.to_string(name),
              feature: Atom.to_string(Map.get(@effective_names, name, name)),
              description: description,
              actor_type: actor_type,
              actor_id: if(actor, do: actor.id),
              enabled: evaluate_flag(name, actor, flags)
            }
          end)

        {:ok,
         %{
           environment: Atom.to_string(Environment.env()),
           resource: %{account_id: account.id, project_id: if(project, do: project.id)},
           evaluations: evaluations
         }}
      end)
    end
  end

  defp evaluation_actor("account", account, _project), do: account
  defp evaluation_actor("project", _account, project), do: project
  defp evaluation_actor("global", _account, _project), do: nil

  defp evaluation_target(params) when is_map(params) and map_size(params) == 1 do
    case Map.to_list(params) do
      [{type, id}] when type in ~w(account_id project_id) ->
        case resource_id(id) do
          {:ok, id} -> {:ok, {type, id}}
          :error -> {:error, :invalid_target}
        end

      _ ->
        {:error, :invalid_target}
    end
  end

  defp evaluation_target(_params), do: {:error, :invalid_target}

  defp resource_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: {:ok, id}

  defp resource_id(id) when is_binary(id) and byte_size(id) in 1..19 do
    case Integer.parse(id) do
      {id, ""} -> resource_id(id)
      _ -> :error
    end
  end

  defp resource_id(_id), do: :error

  # Workload-authenticated, cross-tenant operator inspection. A project lookup
  # resolves its owning account in the same query, never from caller hints.
  defp resource("account_id", id) do
    case Repo.get(Account, id) do
      nil -> {:error, :resource_not_found}
      account -> {:ok, {account, nil}}
    end
  end

  defp resource("project_id", id) do
    query = from(p in Project, join: a in Account, on: a.id == p.account_id, where: p.id == ^id, select: {a, p})

    case Repo.one(query) do
      nil -> {:error, :resource_not_found}
      resource -> {:ok, resource}
    end
  end

  defp evaluate_flag(name, actor, flags)
       when name in [:qa_billing_enabled, :build_entities_kill_switch, :runner_pod_reconciliation_paused],
       do: FeatureFlags.flag_enabled?(name, actor, flags)

  defp evaluate_flag(name, actor, flags) do
    {module, function} = Map.fetch!(@evaluators, name)
    apply(module, function, if(is_nil(actor), do: [flags], else: [actor, flags]))
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
  rescue
    error in Postgrex.Error ->
      if match?(%{code: :lock_not_available}, error.postgres) do
        {:error, :persistence_failed}
      else
        reraise error, __STACKTRACE__
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

    revisions =
      from(change in FeatureFlagChange,
        group_by: change.flag_name,
        select: %{flag_name: change.flag_name, version: max(change.id)}
      )

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
      nil ->
        if Regex.match?(@uncataloged_name, name),
          do: {:ok, {String.to_atom(name), "any", @uncataloged_description}},
          else: {:error, :invalid_flag_name}

      entry ->
        {:ok, entry}
    end
  end

  defp entry(_), do: {:error, :invalid_flag_name}

  defp validate_request(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @fields)),
         true <- params["operation"] in ~w(enable disable clear),
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

  defp gate(_entry, %{"scope" => "all", "operation" => "clear"} = params) do
    if target_fields(params) == %{}, do: {:ok, :all}, else: {:error, :invalid_target}
  end

  defp gate(_entry, %{"scope" => "global"} = params) do
    if target_fields(params) == %{},
      do: {:ok, Gate.new(:boolean, params["operation"] == "enable")},
      else: {:error, :invalid_target}
  end

  defp gate({_, actor_type, _}, %{"scope" => "account", "account_id" => id} = params)
       when actor_type in ["account", "any"] and is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 do
    if target_fields(params) == %{"account_id" => id} and Repo.exists?(from(a in Account, where: a.id == ^id)),
      do: {:ok, Gate.new(:actor, %Account{id: id}, params["operation"] == "enable")},
      else: {:error, :invalid_target}
  end

  defp gate({_, actor_type, _}, %{"scope" => "project", "project_id" => id} = params)
       when actor_type in ["project", "any"] and is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 do
    if target_fields(params) == %{"project_id" => id} and Repo.exists?(from(p in Project, where: p.id == ^id)),
      do: {:ok, Gate.new(:actor, %Project{id: id}, params["operation"] == "enable")},
      else: {:error, :invalid_target}
  end

  defp gate({_, actor_type, _}, %{"scope" => "percentage", "operation" => "enable", "percentage" => percentage} = params)
       when actor_type != "global" and is_number(percentage) and percentage > 0 and percentage < 100 and
              percentage / 100 > 0 and percentage / 100 < 1 do
    if target_fields(params) == %{"percentage" => percentage},
      do: {:ok, Gate.new(:percentage_of_actors, percentage / 100)},
      else: {:error, :invalid_target}
  end

  defp gate({_, actor_type, _}, %{"scope" => "percentage", "operation" => "clear"} = params)
       when actor_type != "global" do
    if target_fields(params) == %{},
      do: {:ok, Gate.new(:percentage_of_actors, 0.5)},
      else: {:error, :invalid_target}
  end

  defp gate(_entry, _params), do: {:error, :invalid_target}
  defp target_fields(params), do: Map.take(params, ~w(account_id project_id percentage))
  defp json_map(value), do: value |> JSON.encode!() |> JSON.decode!()
end
