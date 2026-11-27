defmodule LuftServer.Workspaces.Behaviors do
  @moduledoc "Opt-in, organization-local behavior releases and transactional resources."

  alias LuftServer.Git
  alias LuftServer.Workspaces.BehaviorDefinition, as: Contract
  alias LuftServer.Workspaces.BehaviorJavaScript, as: JavaScript
  alias LuftServer.Workspaces.Definition, as: D
  alias LuftServer.Workspaces.Local

  @lock 179_393_102

  def configured?(scope) do
    Application.get_env(:luft_server, :behavior_workspaces, %{})
    |> Map.has_key?({scope.organization_id, scope.account_id})
  end

  def for_scope(scope, operation, body \\ %{}) do
    bindings = Application.get_env(:luft_server, :behavior_workspaces, %{})

    case bindings[{scope.organization_id, scope.account_id}] do
      database when is_binary(database) ->
        connection = Local.connect!(database)

        try do
          request(connection, scope, operation, body)
        after
          GenServer.stop(connection)
        end

      _ ->
        unconfigured(operation)
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  # An account without a behavior workspace has no collections or releases yet;
  # listing them is empty rather than a refusal. Everything else stays refused.
  defp unconfigured(:catalog), do: {:ok, %{"release" => nil, "collections" => []}}
  defp unconfigured(:releases), do: {:ok, %{"active" => nil, "releases" => []}}
  defp unconfigured(_), do: {:error, :forbidden}

  # Provisioning is a trusted local operation, never an HTTP capability.
  def initialize(connection, organization_id, account_id, principals) do
    transaction(connection, fn tx ->
      sql(tx, "SELECT pg_advisory_xact_lock(#{@lock})")

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS behavior_installation (singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), organization_id bigint NOT NULL, account_id bigint NOT NULL, active text, disabled boolean NOT NULL DEFAULT false)"
      )

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS behavior_principals (user_id bigint PRIMARY KEY, grants jsonb NOT NULL)"
      )

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS behavior_releases (hash text PRIMARY KEY, definition jsonb NOT NULL, runtime text NOT NULL, baseline text, author bigint NOT NULL, reviewer bigint, activated_at timestamptz, created_at timestamptz NOT NULL DEFAULT now())"
      )

      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS repository_key text")
      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS commit_id text")
      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS reviewed_commit_id text")
      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS base_commit_id text")
      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS merge_status text")
      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS merge_requested_by bigint")
      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS merged_by bigint")
      sql(tx, "ALTER TABLE behavior_releases ADD COLUMN IF NOT EXISTS merged_at timestamptz")
      sql(tx, "ALTER TABLE behavior_installation ADD COLUMN IF NOT EXISTS merged text")

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS behavior_invocations (id uuid PRIMARY KEY, user_id bigint NOT NULL, request_id uuid NOT NULL, method text NOT NULL, release text NOT NULL, input jsonb NOT NULL, result jsonb NOT NULL, UNIQUE(user_id,request_id))"
      )

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS behavior_versions (resource text NOT NULL, id uuid NOT NULL, revision bigint NOT NULL, schema_version bigint NOT NULL, release text NOT NULL, invocation uuid NOT NULL REFERENCES behavior_invocations(id) DEFERRABLE INITIALLY DEFERRED, snapshot jsonb NOT NULL, PRIMARY KEY(resource,id,revision))"
      )

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS behavior_events (id bigserial PRIMARY KEY, user_id bigint NOT NULL, kind text NOT NULL, target text NOT NULL, invocation uuid, created_at timestamptz NOT NULL DEFAULT now())"
      )

      sql(
        tx,
        "INSERT INTO behavior_installation (organization_id,account_id) VALUES($1,$2) ON CONFLICT DO NOTHING",
        [organization_id, account_id]
      )

      [[^organization_id, ^account_id]] =
        sql(tx, "SELECT organization_id,account_id FROM behavior_installation").rows

      Enum.each(principals, fn {id, grants} ->
        sql(
          tx,
          "INSERT INTO behavior_principals VALUES($1,$2) ON CONFLICT(user_id) DO UPDATE SET grants=EXCLUDED.grants",
          [id, grants]
        )
      end)

      :ok
    end)
  end

  def request(connection, scope, operation, body \\ %{}) do
    if Contract.bounded?(body) or operation in [:propose, :validate] do
      perform(connection, scope, operation, body)
    else
      {:error, :invalid_request}
    end
  rescue
    _ in [ArgumentError, KeyError, MatchError, FunctionClauseError] -> {:error, :invalid_request}
  end

  defp perform(
         connection,
         scope,
         operation,
         %{"definition" => definition, "baseline" => baseline} = body
       )
       when operation in [:propose, :validate] and map_size(body) == 2 do
    # Check admission before consuming compiler capacity. Recheck after compilation.
    with {:ok, :ok} <-
           transaction(connection, fn tx ->
             {_, active} = authorize!(tx, scope, "author")
             require!(tx, active == baseline, :revision_conflict)
             require_proposable!(tx, active)
           end),
         diagnostics <- validate_definition(definition),
         {:ok, pin} <-
           proposal_pin(connection, scope, operation, definition, baseline, diagnostics) do
      transaction(connection, fn tx ->
        {_, active} = authorize!(tx, scope, "author")
        require!(tx, active == baseline, :revision_conflict)
        require_proposable!(tx, active)

        if operation == :validate do
          validation(tx, active, definition, diagnostics)
        else
          require!(tx, diagnostics == [], :invalid_request)
          freeze(tx, scope, definition, baseline, pin)
        end
      end)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform(
         connection,
         scope,
         :invoke,
         %{"method" => name, "request_id" => request_id, "input" => input} = body
       )
       when map_size(body) == 3 do
    with true <- D.uuid?(request_id),
         {:ok, %{method: method, release: release}} <-
           transaction(connection, fn tx ->
             {grants, active} = authorize!(tx, scope)
             definition = definition!(tx, active)
             require!(tx, name in grants["methods"], :forbidden)
             method = definition["methods"][name]
             require!(tx, is_map(method), :not_found)
             require!(tx, method["resource"] in grants["collections"], :forbidden)

             require!(
               tx,
               Contract.validate_input(method["input"], input) == :ok,
               :invalid_request
             )

             %{method: method, release: active}
           end),
         {:ok, compiled} <- JavaScript.compile(method["source"]) do
      transaction(connection, fn tx ->
        {grants, active} = authorize!(tx, scope)

        require!(
          tx,
          name in grants["methods"] and method["resource"] in grants["collections"],
          :forbidden
        )

        # Check replay before baseline: a committed result survives an additive activation.
        existing =
          sql(
            tx,
            "SELECT method,input,result FROM behavior_invocations WHERE user_id=$1 AND request_id=$2::text::uuid",
            [scope.user_id, request_id]
          ).rows

        case existing do
          [[^name, ^input, result]] ->
            project(
              result,
              definition!(tx, active)["resources"][method["resource"]]["projection"]
            )

          [[_, _, _]] ->
            Postgrex.rollback(tx, :revision_conflict)

          [] ->
            require!(tx, active == release, :revision_conflict)
            definition = definition!(tx, active)
            invocation = Ecto.UUID.generate()

            context = %{
              tx: tx,
              scope: scope,
              grants: grants,
              definition: definition,
              release: active,
              invocation: invocation,
              method: method
            }

            execute(context, compiled, input, name, request_id)
        end
      end)
    else
      false -> {:error, :invalid_request}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :execution_failed}
    end
  end

  defp perform(connection, scope, operation, %{"hash" => hash} = body)
       when operation in [:approve, :activate] and map_size(body) == 1 do
    with {:ok, candidate} <-
           transaction(connection, fn tx ->
             {grants, active} = authorize!(tx, scope)
             review_candidate!(tx, scope, grants, active, operation, hash)
           end),
         {:ok, _} <-
           verify_review(
             operation,
             scope,
             snapshot(
               scope,
               hash,
               candidate.definition,
               candidate.baseline,
               candidate.pin["base_commit_id"]
             ),
             candidate.pin
           ) do
      transaction(connection, fn tx ->
        {grants, active} = authorize!(tx, scope)
        current = review_candidate!(tx, scope, grants, active, operation, hash)
        require!(tx, current == candidate, :revision_conflict)

        if operation == :approve do
          sql(
            tx,
            "UPDATE behavior_releases SET reviewer=$2,reviewed_commit_id=$3 WHERE hash=$1",
            [
              hash,
              scope.user_id,
              current.pin["commit_id"]
            ]
          )
        else
          previous = stored_definition(tx, active)
          require!(tx, Contract.compatible?(previous, current.definition), :incompatible_release)
          install(tx, previous, current.definition)
          sql(tx, "UPDATE behavior_installation SET active=$1", [hash])
          sql(tx, "UPDATE behavior_releases SET activated_at=now() WHERE hash=$1", [hash])
        end

        event(tx, scope, Atom.to_string(operation), hash)
        %{"hash" => hash, "state" => if(operation == :approve, do: "approved", else: "active")}
      end)
    end
  end

  defp perform(connection, scope, :merge, %{"hash" => hash} = body) when map_size(body) == 1 do
    # Persist intent before the external write. A timeout is not evidence that
    # main did not advance; only an explicit retry reconciles this exact pin.
    with {:ok, candidate} <-
           transaction(connection, fn tx ->
             sql(tx, "SELECT singleton FROM behavior_installation FOR UPDATE")
             {grants, active} = authorize!(tx, scope)
             candidate = review_candidate!(tx, scope, grants, active, :merge, hash)

             [[status]] =
               sql(tx, "SELECT merge_status FROM behavior_releases WHERE hash=$1", [hash]).rows

             if is_nil(status) do
               sql(
                 tx,
                 "UPDATE behavior_releases SET merge_status='pending',merge_requested_by=$2 WHERE hash=$1",
                 [hash, scope.user_id]
               )

               event(tx, scope, "merge_requested", hash)
             end

             candidate
           end) do
      transaction(connection, fn tx ->
        sql(tx, "SELECT singleton FROM behavior_installation FOR UPDATE")
        {grants, active} = authorize!(tx, scope)
        current = review_candidate!(tx, scope, grants, active, :merge, hash)
        require!(tx, current == candidate, :revision_conflict)
        # Keep current installation and principal locks until the bounded Git
        # CAS completes. Permissions cannot be revoked between admission and write.
        result =
          Git.merge(
            scope,
            snapshot(
              scope,
              hash,
              current.definition,
              current.baseline,
              current.pin["base_commit_id"]
            ),
            current.pin
          )

        finish_merge(tx, scope, hash, result)
      end)
      |> case do
        {:ok, {:merge_conflict, _}} -> {:error, :revision_conflict}
        other -> other
      end
    end
  end

  defp perform(connection, scope, operation, body) do
    transaction(connection, fn tx ->
      {grants, active} = authorize!(tx, scope)
      dispatch(tx, scope, grants, active, operation, body)
    end)
  end

  defp verify_review(:approve, scope, snapshot, pin), do: Git.verify(scope, snapshot, pin)
  defp verify_review(:activate, scope, snapshot, pin), do: Git.merged(scope, snapshot, pin)

  defp finish_merge(tx, scope, hash, {:ok, _}) do
    rows =
      sql(
        tx,
        "UPDATE behavior_releases SET merge_status='merged',merged_by=$2,merged_at=now() WHERE hash=$1 AND merged_at IS NULL RETURNING hash",
        [hash, scope.user_id]
      ).rows

    sql(tx, "UPDATE behavior_installation SET merged=$1", [hash])
    if rows != [], do: event(tx, scope, "merged", hash)
    %{"hash" => hash, "state" => "merged"}
  end

  defp finish_merge(tx, scope, hash, {:error, :revision_conflict}) do
    sql(
      tx,
      "UPDATE behavior_releases SET merge_status='conflict' WHERE hash=$1 AND merged_at IS NULL",
      [hash]
    )

    event(tx, scope, "merge_conflict", hash)
    {:merge_conflict, hash}
  end

  defp finish_merge(_tx, _scope, _hash, error), do: error

  defp require_proposable!(tx, active) do
    [[merged]] = sql(tx, "SELECT merged FROM behavior_installation").rows
    require!(tx, is_nil(merged) or merged == active, :revision_conflict)

    require!(
      tx,
      sql(tx, "SELECT hash FROM behavior_releases WHERE merge_status='pending' LIMIT 1").rows ==
        [],
      :revision_conflict
    )
  end

  defp validate_definition(definition) do
    D.ensure!(byte_size(Jason.encode!(definition)) <= 131_072, "Definition exceeds budget")
    Contract.validate!(definition)

    Enum.flat_map(Enum.sort(definition["methods"]), fn {id, method} ->
      case JavaScript.compile(method["source"]) do
        {:ok, _} ->
          []

        _ ->
          ["#{id}: JavaScript compilation failed. Check the method source and compiler budget."]
      end
    end)
  rescue
    e in ArgumentError -> [Exception.message(e)]
    _ -> ["Invalid behavior definition. Inspect the authoring schema and current definition."]
  end

  defp validation(tx, baseline, definition, []) do
    before = stored_definition(tx, baseline)
    compatible = Contract.compatible?(before, definition)

    %{
      "valid" => true,
      "diagnostics" => [],
      "baseline" => baseline,
      "runtime" => JavaScript.identity(),
      "compatible" => compatible,
      "changes" => Contract.changes(before, definition),
      "blockers" => if(compatible, do: [], else: ["Breaking contracts cannot be activated."])
    }
  end

  defp validation(_tx, baseline, _definition, diagnostics),
    do: %{"valid" => false, "baseline" => baseline, "diagnostics" => diagnostics}

  defp release_hash(scope, definition, baseline, base) do
    Contract.hash(%{
      "storage" => "git-main-v1",
      "base_commit_id" => base,
      "definition" => definition,
      "baseline" => baseline,
      "runtime" => JavaScript.identity(),
      "organization" => scope.organization_id,
      "account" => scope.account_id
    })
  end

  defp snapshot(scope, hash, definition, baseline, base) do
    %{
      "storage" => "git-main-v1",
      "base_commit_id" => base,
      "hash" => hash,
      "definition" => definition,
      "baseline" => baseline,
      "runtime" => JavaScript.identity(),
      "organization_id" => scope.organization_id,
      "account_id" => scope.account_id
    }
  end

  defp proposal_pin(_connection, _scope, :validate, _definition, _baseline, _diagnostics),
    do: {:ok, nil}

  defp proposal_pin(_connection, _scope, :propose, _definition, _baseline, [_ | _]),
    do: {:ok, nil}

  defp proposal_pin(connection, scope, :propose, definition, baseline, []) do
    with {:ok, base} <- Git.main(scope),
         hash = release_hash(scope, definition, baseline, base),
         {:ok, existing} <-
           transaction(connection, fn tx ->
             {_, active} = authorize!(tx, scope, "author")
             require!(tx, active == baseline, :revision_conflict)
             require_proposable!(tx, active)
             stored_pin(tx, hash)
           end),
         {:ok, pin} <-
           Git.publish(
             scope,
             snapshot(scope, hash, definition, baseline, base),
             base,
             existing
           ) do
      {:ok, Map.put(pin, "base_commit_id", base)}
    end
  end

  defp stored_pin(_tx, nil), do: nil

  defp stored_pin(tx, hash) do
    case sql(
           tx,
           "SELECT repository_key,commit_id,base_commit_id FROM behavior_releases WHERE hash=$1",
           [hash]
         ).rows do
      [[key, commit, base]] when is_binary(key) and is_binary(commit) ->
        %{"repository_key" => key, "commit_id" => commit, "base_commit_id" => base}

      _ ->
        nil
    end
  end

  defp freeze(tx, scope, definition, baseline, pin) do
    hash = release_hash(scope, definition, baseline, pin["base_commit_id"])

    inserted =
      sql(
        tx,
        "INSERT INTO behavior_releases(hash,definition,runtime,baseline,author,repository_key,commit_id,base_commit_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT DO NOTHING RETURNING hash",
        [
          hash,
          definition,
          JavaScript.identity(),
          baseline,
          scope.user_id,
          pin["repository_key"],
          pin["commit_id"],
          pin["base_commit_id"]
        ]
      ).rows

    require!(tx, stored_pin(tx, hash) == pin, :revision_conflict)
    if inserted != [], do: event(tx, scope, "proposed", hash)
    Map.merge(%{"hash" => hash, "baseline" => baseline}, pin)
  end

  defp execute(context, compiled, input, name, request_id) do
    %{tx: tx, scope: scope, invocation: invocation, definition: definition, method: method} =
      context

    case JavaScript.execute(compiled, input, &callback(context, &1, &2)) do
      {:ok, result} when is_map(result) ->
        changed =
          sql(tx, "SELECT snapshot FROM behavior_versions WHERE invocation=$1::text::uuid", [
            invocation
          ]).rows

        require!(tx, match?([[_]], changed), :invalid_result)
        [[snapshot]] = changed

        require!(
          tx,
          result == project(snapshot, definition["resources"][method["resource"]]["projection"]),
          :invalid_result
        )

        sql(
          tx,
          "INSERT INTO behavior_invocations VALUES($1::text::uuid,$2,$3::text::uuid,$4,$5,$6,$7)",
          [invocation, scope.user_id, request_id, name, context.release, input, result]
        )

        event(tx, scope, "invoked", name, invocation)
        result

      _ ->
        Postgrex.rollback(tx, :execution_failed)
    end
  end

  defp review_candidate!(tx, scope, grants, active, operation, hash) do
    # The installation lock serializes activation, admission and permission changes.
    require!(tx, operation |> Atom.to_string() |> then(&(&1 in grants["roles"])), :forbidden)

    rows =
      sql(tx, "SELECT to_jsonb(r) FROM behavior_releases r WHERE hash=$1 FOR UPDATE", [hash]).rows

    require!(tx, rows != [], :not_found)
    [[release]] = rows
    definition = release["definition"]
    baseline = release["baseline"]
    author = release["author"]
    reviewer = release["reviewer"]
    require!(tx, release["runtime"] == JavaScript.identity(), :incompatible_release)
    require!(tx, baseline == active and is_nil(release["activated_at"]), :revision_conflict)
    pin = stored_pin(tx, hash)
    require!(tx, not is_nil(pin), :revision_conflict)

    require!(
      tx,
      hash == release_hash(scope, definition, baseline, pin["base_commit_id"]),
      :revision_conflict
    )

    owners = definition["resources"] |> Map.keys() |> Enum.map(&Contract.owner/1) |> Enum.uniq()

    if operation == :approve do
      require!(tx, is_nil(release["merge_status"]), :revision_conflict)
      require!(tx, author != scope.user_id and owners -- grants["owners"] == [], :forbidden)
    else
      require!(tx, reviewed?(tx, reviewer, author, owners), :forbidden)
      require!(tx, release["reviewed_commit_id"] == pin["commit_id"], :revision_conflict)

      require!(
        tx,
        Contract.compatible?(stored_definition(tx, active), definition),
        :incompatible_release
      )

      require_merge_state!(tx, hash, active, operation, release["merge_status"])
    end

    %{
      definition: definition,
      baseline: baseline,
      reviewer: reviewer,
      pin: pin
    }
  end

  defp require_merge_state!(tx, hash, active, :merge, status) do
    require!(tx, status in [nil, "pending", "merged"], :revision_conflict)
    [[merged]] = sql(tx, "SELECT merged FROM behavior_installation").rows
    require!(tx, merged in [nil, active, hash], :revision_conflict)

    require!(
      tx,
      sql(
        tx,
        "SELECT hash FROM behavior_releases WHERE merge_status='pending' AND hash<>$1 LIMIT 1",
        [hash]
      ).rows == [],
      :revision_conflict
    )
  end

  defp require_merge_state!(tx, hash, _active, :activate, status) do
    require!(tx, status == "merged", :revision_conflict)
    [[merged]] = sql(tx, "SELECT merged FROM behavior_installation").rows
    require!(tx, merged == hash, :revision_conflict)
  end

  defp dispatch(tx, _scope, grants, active, :catalog, body) when map_size(body) == 0 do
    definition =
      if active, do: definition!(tx, active), else: %{"resources" => %{}, "methods" => %{}}

    %{
      "release" => active,
      "collections" =>
        definition["resources"]
        |> Enum.filter(fn {id, _} -> id in grants["collections"] end)
        |> Enum.sort()
        |> Enum.map(fn {id, _} -> descriptor(definition, grants, id) end)
    }
  end

  defp dispatch(tx, _scope, grants, active, :authoring, body) when map_size(body) == 0 do
    require!(tx, "author" in grants["roles"], :forbidden)

    %{
      "active" => active,
      "merged" => merged_release(tx),
      "definition" => stored_definition(tx, active),
      "schema" => Contract.authoring_schema(),
      "runtime" => JavaScript.identity(),
      "roles" => grants["roles"],
      "owners" => grants["owners"],
      "constraints" => [
        "Definitions are authored content shared with this conversation, never secrets or resource snapshots.",
        "Resource and method IDs use namespace.name; a method writes only its own resource.",
        "JavaScript receives input; await Javex.Host.call(name, body) supports resources.get/create/update only.",
        "Writes require values; updates also require id and expected_revision. Return the projected record. One mutation per invocation.",
        "Cross-owner reads require an export from the resource owner and the caller's collection grant.",
        "Validation compiles but does not execute JavaScript or test its business behavior.",
        "Only additive contracts activate: preserve existing methods, field types, projections, indexes and exports; bump modified resource versions by one.",
        "Definitions are at most 131072 UTF-8 bytes; each method source is at most 32768 bytes.",
        "Propose against the current active hash (null for first release); independent human review precedes merge into ops/main, then explicit activation.",
        "After main moves, repropose and obtain fresh review. Activate or reconcile this account's pending merge before proposing another change."
      ]
    }
  end

  defp dispatch(tx, scope, grants, active, :releases, body) when map_size(body) == 0 do
    require!(
      tx,
      Enum.any?(~w(author approve merge activate), &(&1 in grants["roles"])),
      :forbidden
    )

    %{
      "active" => active,
      "releases" =>
        sql(
          tx,
          "SELECT to_jsonb(r) FROM behavior_releases r ORDER BY created_at DESC,hash LIMIT 20"
        ).rows
        |> Enum.map(fn [release] -> release_metadata(tx, scope, grants, active, release) end)
    }
  end

  defp dispatch(tx, scope, grants, active, :release, %{"hash" => hash} = body)
       when map_size(body) == 1 and is_binary(hash) do
    require!(
      tx,
      Enum.any?(~w(author approve merge activate), &(&1 in grants["roles"])),
      :forbidden
    )

    rows = sql(tx, "SELECT to_jsonb(r) FROM behavior_releases r WHERE hash=$1", [hash]).rows
    require!(tx, rows != [], :not_found)
    [[release]] = rows
    before = stored_definition(tx, release["baseline"])

    tx
    |> release_metadata(scope, grants, active, release)
    |> Map.merge(%{
      "runtime" => release["runtime"],
      "definition" => release["definition"],
      "baseline_definition" => before,
      "changes" => Contract.changes(before, release["definition"])
    })
  end

  defp dispatch(tx, _scope, grants, active, operation, %{"collection" => id} = body)
       when operation in [:get, :query] do
    definition = definition!(tx, active)
    schema = definition["resources"][id]
    require!(tx, is_map(schema) and id in grants["collections"], :forbidden)

    case operation do
      :get ->
        require!(tx, Map.keys(body) -- ~w(collection id version) == [], :invalid_request)
        require!(tx, D.uuid?(body["id"]), :invalid_request)
        record = read(tx, id, body["id"], body["version"])

        %{
          "release" => active,
          "record" => project(record, schema["projection"]),
          "collection" =>
            if(is_nil(body["version"]),
              do: descriptor(definition, grants, id),
              else: Map.put(descriptor(definition, grants, id), "methods", [])
            ),
          "historical" => not is_nil(body["version"])
        }

      :query ->
        list(tx, id, schema, Map.delete(body, "collection"))
    end
  end

  defp dispatch(_, _, _, _, _, _), do: {:error, :invalid_request}

  defp release_metadata(tx, scope, grants, active, release) do
    owners = release["definition"]["resources"] |> Map.keys() |> Enum.map(&Contract.owner/1)

    compatible =
      Contract.compatible?(stored_definition(tx, release["baseline"]), release["definition"])

    eligible = release["baseline"] == active and is_nil(release["activated_at"])
    runtime_matches = release["runtime"] == JavaScript.identity()
    reviewer = release["reviewer"]
    pinned = is_binary(release["repository_key"]) and is_binary(release["commit_id"])

    reviewed =
      pinned and release["reviewed_commit_id"] == release["commit_id"] and
        reviewed?(tx, reviewer, release["author"], owners)

    common =
      [
        {not pinned, "This release has no Git commit; propose it again for fresh review."},
        {release["hash"] == active, "This release is already active."},
        {not is_nil(release["activated_at"]) and release["hash"] != active,
         "Previously activated releases cannot be reactivated."},
        {release["baseline"] != active and release["hash"] != active,
         "The active baseline has changed; author a new proposal."},
        {not runtime_matches, "The JavaScript runtime has changed; author a new proposal."},
        {not compatible, "Breaking contracts cannot be activated."},
        {not reviewed,
         "An independent reviewer with current owner grants must approve this hash."}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    merged = release["merge_status"] == "merged" and merged_release(tx) == release["hash"]

    merge_allowed =
      release["merge_status"] in [nil, "pending"] and merge_slot?(tx, active, release["hash"])

    merge_blockers =
      common ++
        if("merge" in grants["roles"],
          do: [],
          else: ["You do not have permission to merge releases."]
        ) ++
        if(merge_allowed,
          do: [],
          else: [
            "Activate or reconcile the pending merge, or propose again after a main conflict."
          ]
        )

    blockers =
      common ++
        if(merged, do: [], else: ["Merge this reviewed commit into ops/main before activation."]) ++
        if("activate" in grants["roles"],
          do: [],
          else: ["You do not have permission to activate releases."]
        )

    %{
      "hash" => release["hash"],
      "baseline" => release["baseline"],
      "repository_key" => release["repository_key"],
      "commit_id" => release["commit_id"],
      "reviewed_commit_id" => release["reviewed_commit_id"],
      "base_commit_id" => release["base_commit_id"],
      "merged_at" => release["merged_at"],
      "merged_by" => release["merged_by"],
      "merge_requested_by" => release["merge_requested_by"],
      "title" => release["definition"]["title"],
      "author" => release["author"],
      "reviewer" => reviewer,
      "active_at" => release["activated_at"],
      "created_at" => release["created_at"],
      "state" => release_state(release, active, reviewed),
      "compatible" => compatible,
      "can_approve" =>
        is_nil(release["merge_status"]) and pinned and eligible and runtime_matches and
          "approve" in grants["roles"] and
          scope.user_id != release["author"] and owners -- grants["owners"] == [],
      "can_merge" => merge_blockers == [],
      "merge_blockers" => merge_blockers,
      "can_activate" => blockers == [],
      "blockers" => blockers
    }
  end

  defp release_state(release, active, reviewed) do
    cond do
      release["hash"] == active -> "active"
      not is_nil(release["activated_at"]) -> "superseded"
      release["baseline"] != active -> "stale"
      release["merge_status"] == "conflict" -> "merge_conflict"
      release["merge_status"] == "pending" -> "merging"
      release["merge_status"] == "merged" -> "merged"
      reviewed -> "approved"
      true -> "proposed"
    end
  end

  defp merged_release(tx) do
    [[hash]] = sql(tx, "SELECT merged FROM behavior_installation").rows
    hash
  end

  defp merge_slot?(tx, active, hash) do
    merged_release(tx) in [nil, active, hash] and
      sql(
        tx,
        "SELECT hash FROM behavior_releases WHERE merge_status='pending' AND hash<>$1 LIMIT 1",
        [hash]
      ).rows == []
  end

  defp stored_definition(_tx, nil), do: nil

  defp stored_definition(tx, hash) do
    [[definition]] =
      sql(tx, "SELECT definition FROM behavior_releases WHERE hash=$1", [hash]).rows

    definition
  end

  defp reviewed?(_tx, reviewer, author, _owners) when is_nil(reviewer) or reviewer == author,
    do: false

  defp reviewed?(tx, reviewer, _author, owners) do
    case sql(tx, "SELECT grants FROM behavior_principals WHERE user_id=$1 FOR SHARE", [reviewer]).rows do
      [[grants]] -> "approve" in grants["roles"] and owners -- grants["owners"] == []
      [] -> false
    end
  end

  defp callback(context, name, body) do
    %{tx: tx, definition: definition, method: method, grants: grants} = context
    require!(tx, Contract.bounded?(body) and is_map(body), :invalid_request)
    id = body["resource"] || method["resource"]
    schema = definition["resources"][id]
    require!(tx, is_map(schema), :forbidden)
    own? = Contract.owner(id) == Contract.owner(method["resource"])

    projection =
      if own?,
        do: schema["projection"],
        else: schema["exports"][Contract.owner(method["resource"])]

    require!(tx, is_list(projection), :forbidden)

    # Exports are explicit data-owner consent; independent actor read permission is still required.
    require!(tx, id in grants["collections"], :forbidden)

    result =
      case name do
        "resources.get" ->
          require!(
            tx,
            Map.keys(body) -- ~w(resource id) == [] and D.uuid?(body["id"]),
            :invalid_request
          )

          read(tx, id, body["id"], nil)

        write when write in ~w(resources.create resources.update) ->
          require!(
            tx,
            own? and id == method["resource"] and
              Map.keys(body) -- ~w(resource id expected_revision values) == [],
            :forbidden
          )

          mutate(context, id, schema, write, body)
      end

    {:ok, project(result, projection)}
  end

  defp mutate(context, id, schema, operation, body) do
    tx = context.tx

    require!(
      tx,
      sql(tx, "SELECT 1 FROM behavior_versions WHERE invocation=$1::text::uuid", [
        context.invocation
      ]).rows == [],
      :mutation_limit
    )

    fields = schema["fields"]
    values = body["values"]
    require!(tx, is_map(values) and Map.keys(values) -- Map.keys(fields) == [], :invalid_request)
    create? = operation == "resources.create"
    require!(tx, not create? or not Map.has_key?(body, "id"), :invalid_request)
    record_id = if create?, do: Ecto.UUID.generate(), else: body["id"]
    require!(tx, D.uuid?(record_id), :invalid_request)
    previous = if create?, do: %{}, else: read(tx, id, record_id, nil)
    require!(tx, create? or body["expected_revision"] == previous["revision"], :revision_conflict)
    require!(tx, previous["deleted"] != true, :not_found)

    data =
      if create?,
        do: Map.new(fields, fn {key, field} -> {key, Map.get(values, key, field["default"])} end),
        else: Map.merge(Map.take(previous, Map.keys(fields)), values)

    require!(
      tx,
      Enum.all?(data, fn {key, value} -> D.valid_value?(fields[key], value) end),
      :validation_failed
    )

    Enum.each(data, fn {key, value} ->
      case fields[key] do
        %{"type" => "reference", "model" => target} when not is_nil(value) ->
          require!(tx, target in context.grants["collections"], :forbidden)
          _ = read(tx, target, value, nil)

        _ ->
          :ok
      end
    end)

    keys = data |> Map.keys() |> Enum.sort()

    parameters =
      Enum.map(keys, fn key ->
        if fields[key]["type"] == "reference" and data[key],
          do: Ecto.UUID.dump!(data[key]),
          else: data[key]
      end)

    record =
      if create? do
        columns = Enum.map_join(["id" | keys], ",", &D.quote_id/1)
        placeholders = Enum.map_join(1..(length(keys) + 1), ",", &"$#{&1}")

        [[record]] =
          sql(
            tx,
            "INSERT INTO #{Contract.table(id)} AS r (#{columns}) VALUES(#{placeholders}) RETURNING to_jsonb(r)",
            [Ecto.UUID.dump!(record_id) | parameters]
          ).rows

        record
      else
        assignments =
          keys
          |> Enum.with_index(1)
          |> Enum.map_join(",", fn {key, n} -> "#{D.quote_id(key)}=$#{n}" end)

        [[record]] =
          sql(
            tx,
            "UPDATE #{Contract.table(id)} r SET #{assignments},revision=revision+1 WHERE id=$#{length(keys) + 1}::text::uuid AND revision=$#{length(keys) + 2} RETURNING to_jsonb(r)",
            parameters ++ [record_id, previous["revision"]]
          ).rows

        record
      end

    sql(
      tx,
      "INSERT INTO behavior_versions VALUES($1,$2::text::uuid,$3,$4,$5,$6::text::uuid,$7)",
      [
        id,
        record_id,
        record["revision"],
        schema["version"],
        context.release,
        context.invocation,
        record
      ]
    )

    record
  end

  defp read(tx, id, record_id, nil) do
    case sql(
           tx,
           "SELECT to_jsonb(r) FROM #{Contract.table(id)} r WHERE id=$1::text::uuid AND NOT deleted",
           [record_id]
         ).rows do
      [[record]] -> record
      [] -> Postgrex.rollback(tx, :not_found)
    end
  end

  defp read(tx, id, record_id, version) do
    require!(tx, is_integer(version) and version > 0, :invalid_request)

    case sql(
           tx,
           "SELECT snapshot FROM behavior_versions WHERE resource=$1 AND id=$2::text::uuid AND revision=$3",
           [id, record_id, version]
         ).rows do
      [[record]] -> record
      [] -> Postgrex.rollback(tx, :not_found)
    end
  end

  defp list(tx, id, schema, body) do
    require!(
      tx,
      Map.keys(body) -- ~w(search filters sort direction offset limit) == [],
      :invalid_request
    )

    filters = body["filters"] || %{}
    sort = body["sort"] || List.first(schema["sort"]) || "id"
    direction = body["direction"] || "asc"
    offset = body["offset"] || 0
    limit = body["limit"] || 20
    search = body["search"] || ""

    require!(
      tx,
      is_map(filters) and Map.keys(filters) -- schema["filters"] == [] and is_binary(search) and
        byte_size(search) <= 200 and direction in ~w(asc desc) and sort in ["id" | schema["sort"]] and
        is_integer(offset) and offset in 0..10_000 and is_integer(limit) and limit in 1..50,
      :invalid_request
    )

    {conditions, parameters} =
      Enum.reduce(Enum.sort(filters), {["NOT deleted"], []}, fn {field, value},
                                                                {clauses, params} ->
        require!(
          tx,
          is_binary(value) and D.valid_value?(schema["fields"][field], value),
          :invalid_request
        )

        {["#{D.quote_id(field)}::text=$#{length(params) + 1}" | clauses], params ++ [value]}
      end)

    {conditions, parameters} =
      if search == "" do
        {conditions, parameters}
      else
        require!(tx, schema["search"] != [], :invalid_request)

        clause =
          Enum.map_join(
            schema["search"],
            " OR ",
            &"strpos(lower(#{D.quote_id(&1)}::text),lower($#{length(parameters) + 1}))>0"
          )

        {["(#{clause})" | conditions], parameters ++ [search]}
      end

    columns = Enum.map_join(["id", "revision" | schema["projection"]], ",", &D.quote_id/1)
    order = D.quote_id(sort) <> " " <> direction <> if(sort == "id", do: "", else: ", id")

    rows =
      sql(
        tx,
        "SELECT to_jsonb(r) FROM (SELECT #{columns} FROM #{Contract.table(id)} WHERE #{Enum.join(conditions, " AND ")} ORDER BY #{order} LIMIT #{limit + 1} OFFSET #{offset}) r",
        parameters
      ).rows
      |> Enum.map(&hd/1)

    %{"items" => Enum.take(rows, limit), "has_more" => length(rows) > limit}
  end

  defp descriptor(definition, grants, id) do
    schema = definition["resources"][id]

    %{
      "id" => id,
      "title" => schema["title"],
      "search" => schema["search"],
      "filters" => schema["filters"],
      "sort" => schema["sort"],
      "fields" =>
        Enum.map(schema["projection"], fn key ->
          %{
            "id" => key,
            "label" => String.capitalize(String.replace(key, "_", " ")),
            "type" => schema["fields"][key]["type"],
            "values" => schema["fields"][key]["values"],
            "target" => schema["fields"][key]["model"]
          }
        end),
      "methods" =>
        definition["methods"]
        |> Enum.filter(fn {name, method} ->
          method["resource"] == id and name in grants["methods"]
        end)
        |> Enum.sort()
        |> Enum.map(fn {name, method} ->
          %{
            "id" => name,
            "label" => method["label"],
            "operation" => method["operation"],
            "input" => method["input"]
          }
        end)
    }
  end

  defp install(tx, previous, definition) do
    Enum.each(definition["resources"], fn {id, schema} ->
      old = get_in(previous || %{}, ["resources", id, "fields"])

      if old do
        Enum.each(Map.drop(schema["fields"], Map.keys(old)), fn {field, type} ->
          sql(tx, "ALTER TABLE #{Contract.table(id)} ADD COLUMN #{column(field, type)}")
        end)
      else
        columns =
          schema["fields"]
          |> Enum.sort()
          |> Enum.map_join(",", fn {field, type} -> column(field, type) end)

        sql(
          tx,
          "CREATE TABLE #{Contract.table(id)}(id uuid PRIMARY KEY, revision bigint NOT NULL DEFAULT 1 CHECK(revision>0), deleted boolean NOT NULL DEFAULT false, #{columns})"
        )
      end

      for field <- Enum.uniq(schema["filters"] ++ schema["sort"]) do
        index = D.quote_id("idx_" <> String.slice(D.hash(id <> field), 0, 24))

        sql(
          tx,
          "CREATE INDEX IF NOT EXISTS #{index} ON #{Contract.table(id)}(#{D.quote_id(field)},id)"
        )
      end
    end)

    # Targets may be declared after their dependants; add constraints once all tables exist.
    Enum.each(definition["resources"], fn {id, schema} ->
      old = get_in(previous || %{}, ["resources", id, "fields"]) || %{}

      for {field, %{"type" => "reference", "model" => target}} <-
            Map.drop(schema["fields"], Map.keys(old)) do
        sql(
          tx,
          "ALTER TABLE #{Contract.table(id)} ADD FOREIGN KEY (#{D.quote_id(field)}) REFERENCES #{Contract.table(target)}(id) ON DELETE RESTRICT"
        )
      end
    end)
  end

  defp column(field, type) do
    name = D.quote_id(field)

    constraint =
      case type["type"] do
        "reference" ->
          ""

        "enum" ->
          values =
            Enum.map_join(type["values"], ",", &("'" <> String.replace(&1, "'", "''") <> "'"))

          " CHECK(#{name} IN (#{values}))"

        "string" ->
          " CHECK(octet_length(#{name})<=4000)"
      end

    name <>
      if(type["type"] == "reference", do: " uuid", else: " text") <>
      if(type["required"] == true or type["nullable"] == false, do: " NOT NULL", else: "") <>
      constraint
  end

  defp project(record, fields), do: Map.take(record, ["id", "revision" | fields])

  defp authorize!(tx, scope, role \\ nil) do
    sql(tx, "SELECT pg_advisory_xact_lock_shared(#{@lock})")

    rows =
      sql(
        tx,
        "SELECT organization_id,account_id,active,disabled FROM behavior_installation FOR SHARE"
      ).rows

    require!(tx, match?([[_, _, _, false]], rows), :forbidden)
    [[organization, account, active, false]] = rows

    require!(
      tx,
      organization == scope.organization_id and account == scope.account_id,
      :forbidden
    )

    grants =
      sql(tx, "SELECT grants FROM behavior_principals WHERE user_id=$1 FOR SHARE", [scope.user_id]).rows

    require!(tx, grants != [], :forbidden)
    [[grants]] = grants
    require!(tx, is_nil(role) or role in grants["roles"], :forbidden)
    {grants, active}
  end

  defp definition!(tx, active) do
    require!(tx, is_binary(active), :not_found)

    [[definition, runtime]] =
      sql(tx, "SELECT definition,runtime FROM behavior_releases WHERE hash=$1", [active]).rows

    require!(tx, runtime == JavaScript.identity(), :incompatible_release)

    definition
  end

  defp event(tx, scope, kind, target, invocation \\ nil),
    do:
      sql(
        tx,
        "INSERT INTO behavior_events(user_id,kind,target,invocation) VALUES($1,$2,$3,$4::text::uuid)",
        [scope.user_id, kind, target, invocation]
      )

  defp require!(tx, condition, reason),
    do: if(condition, do: :ok, else: Postgrex.rollback(tx, reason))

  defp sql(tx, query, params \\ []), do: Postgrex.query!(tx, query, params)

  defp transaction(connection, fun) do
    Postgrex.transaction(
      connection,
      fn tx ->
        sql(tx, "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
        sql(tx, "SET LOCAL statement_timeout='2s'")
        sql(tx, "SET LOCAL lock_timeout='1s'")
        sql(tx, "SET LOCAL idle_in_transaction_session_timeout='8s'")

        case fun.(tx) do
          {:error, reason} -> Postgrex.rollback(tx, reason)
          result -> result
        end
      end,
      timeout: 10_000
    )
  rescue
    e in Postgrex.Error ->
      if e.postgres[:code] in [:serialization_failure, :deadlock_detected, :unique_violation],
        do: {:error, :revision_conflict},
        else: {:error, :unavailable}
  end
end
