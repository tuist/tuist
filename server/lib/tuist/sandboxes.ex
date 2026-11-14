defmodule Tuist.Sandboxes do
  @moduledoc """
  Control plane for Firecracker sandboxes (see `infra/sandboxd/AGENTS.md`).

  Owns the `sandboxes`, `sandbox_agent_environments` and
  `sandbox_agent_sessions` tables and drives the sandboxd nodes through
  `Tuist.Sandboxes.Nodes`. Every state transition here mirrors one node
  command: `create`, `resume`, `pause`, `delete`, `exec`, `start_worker`.
  Node-originated changes arrive as events (`worker_exited`,
  `sandbox_died`) and periodic reports, which reconcile what the database
  believes against what the node holds. Agent sessions started through
  Tuist are delegated to `Tuist.Sandboxes.AgentSessions`.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.AgentSession
  alias Tuist.Sandboxes.AgentSessions
  alias Tuist.Sandboxes.AmpOrbs
  alias Tuist.Sandboxes.Anthropic.ControlPlane
  alias Tuist.Sandboxes.Anthropic.Federation
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Events
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.PauseIdleOrbWorker
  alias Tuist.Sandboxes.Workers.PauseSandboxWorker
  alias Tuist.Tasks

  require Logger

  @default_template "default"
  @default_shape %{vcpus: 2, memory_mb: 4096, workspace_gb: 10}
  @default_pause_grace_seconds 30
  @shared_command_pause_grace_seconds 20
  @create_timeout to_timeout(second: 120)
  @resume_timeout to_timeout(second: 120)
  # A restore downloads the archive before it boots. Amp's dispatch allows
  # 240 seconds per request.
  @restore_timeout to_timeout(second: 200)
  @exec_default_timeout_ms 60_000
  @exec_max_timeout_ms 600_000
  @exec_timeout_slack_ms 10_000
  @exec_output_limit_bytes 1_048_576
  @transient_node_errors [:not_connected, :node_disconnected, :timeout]
  # A row still `creating` or `resuming` this long after its last update
  # belongs to a caller that died mid-operation (a web pod stopped during a
  # deploy): the node's report decides what it is now.
  @stuck_after_seconds 150
  @report_settle_seconds 10
  # Sandboxes are bounded by the account's CPU and memory quota
  # (`Concurrency`) and by each node's disk budget, not by a count.
  # A running Amp Orb whose guest has used under 2% of one vCPU for this
  # long is paused, in case Amp's own pause never arrives.
  @orb_idle_pause_after_seconds 600
  @active_cpu_ms_per_second 20

  def default_template, do: @default_template
  def default_shape, do: @default_shape

  defdelegate dispatch_amp_orb(account, orb_id, params), to: AmpOrbs, as: :dispatch
  defdelegate amp_orb_type(orb_type), to: AmpOrbs, as: :orb_type

  @doc """
  Queues the archive of a paused sandbox (`Tuist.Sandboxes.Archives.request/1`);
  `resume/1` restores it.
  """
  defdelegate archive(sandbox), to: Archives, as: :request
  defdelegate archivable?(sandbox), to: Archives

  # ----- Agent environments -----

  def create_agent_environment(%Account{id: account_id}, attrs) when is_map(attrs) do
    attrs = attrs |> platform_defaults() |> kind_defaults() |> Map.put(:account_id, account_id)

    with {:ok, agent_environment} <- %AgentEnvironment{} |> AgentEnvironment.create_changeset(attrs) |> Repo.insert() do
      reconcile_claude_code(agent_environment)
      {:ok, agent_environment}
    end
  end

  # A Claude Code session keeps its runner, and its sandbox running, for half
  # an hour of idleness unless the environment says otherwise.
  defp kind_defaults(attrs) do
    if Map.get(attrs, :kind) in [:claude_code, "claude_code"],
      do: Map.put_new(attrs, :max_idle_seconds, 1800),
      else: attrs
  end

  defp reconcile_claude_code(%AgentEnvironment{kind: :claude_code}),
    do: {:ok, _job} = Oban.insert(Tuist.Sandboxes.ClaudeCodeReconciler.new(%{}))

  defp reconcile_claude_code(_agent_environment), do: :ok

  @doc "Fills the shape and template `attrs` leave out with the defaults of their platform."
  def platform_defaults(attrs) do
    defaults =
      if Map.get(attrs, :platform) in [:darwin, "darwin"] do
        %{vcpus: 8, memory_mb: 8192, workspace_gb: 10, template: "macos"}
      else
        Map.put(@default_shape, :template, @default_template)
      end

    Map.merge(defaults, attrs |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new())
  end

  def workspace(%{platform: :darwin}), do: "/Users/runner/work"
  def workspace(_sandbox), do: "/workspace"

  @doc """
  The Tuist environment an agent in `sandbox` gets: `TUIST_URL`, and
  `TUIST_CACHE_ENDPOINT` when the account has an in-cluster cache, the same
  URL a runner on the sandbox's Node would use (absent without one). It
  holds no credential: Tuist clients in the guest sign in by exchanging the
  agent's own identity token (an Amp Orb's, or a Claude Code session's).
  """
  def tuist_env(%Account{} = account, %Sandbox{} = sandbox) do
    env = %{"TUIST_URL" => Tuist.Environment.app_url()}
    platform = if sandbox.platform == :darwin, do: :macos, else: :linux

    # Clients treat the endpoint as a hard override, so it is only handed to a
    # platform whose hosts reach the cluster network, as CI dispatch does.
    with true <- platform in Tuist.Environment.runners_cluster_network_platforms(),
         url when is_binary(url) and url != "" <-
           Tuist.Kura.runner_cache_endpoint_url(account, platform, Sites.node_site(sandbox.node_name)) do
      Map.put(env, "TUIST_CACHE_ENDPOINT", url)
    else
      _ -> env
    end
  end

  def list_agent_environments(%Account{id: account_id}) do
    Repo.all(from e in AgentEnvironment, where: e.account_id == ^account_id, order_by: [asc: e.id])
  end

  @doc """
  The account whose enabled Claude Code environment is `environment_id`
  (`ccpool_...`), for exchanging its sessions' identity tokens. Connecting
  the environment for sandboxes is what lets its sessions use the account's
  Tuist cache, as connecting an Amp workspace does for Orbs.
  """
  def claude_code_environment_account(environment_id) when is_binary(environment_id) do
    query =
      from e in AgentEnvironment,
        where: e.anthropic_environment_id == ^environment_id and e.kind == :claude_code and e.enabled,
        preload: [:account]

    case Repo.one(query) do
      %AgentEnvironment{account: account} ->
        if Tuist.FeatureFlags.sandboxes_enabled?(account),
          do: {:ok, account},
          else: {:error, :claude_code_environment_not_connected}

      nil ->
        {:error, :claude_code_environment_not_connected}
    end
  end

  def list_enabled_agent_environments(kind) do
    Repo.all(
      from e in AgentEnvironment,
        where: e.enabled == true and e.kind == ^kind,
        order_by: [asc: e.id],
        preload: [:account]
    )
  end

  def get_agent_environment(%Account{id: account_id}, id) do
    case Repo.get_by(AgentEnvironment, id: id, account_id: account_id) do
      nil -> {:error, :not_found}
      agent_environment -> {:ok, agent_environment}
    end
  end

  def get_agent_environment_by_id(id) do
    case Repo.get(AgentEnvironment, id) do
      nil -> {:error, :not_found}
      agent_environment -> {:ok, agent_environment}
    end
  end

  def update_agent_environment(%AgentEnvironment{} = agent_environment, attrs) when is_map(attrs) do
    agent_environment
    |> AgentEnvironment.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Fetches the self-hosted Managed Agents environment `environment_id`
  from the account's Anthropic workspace, which checks the credential
  before an agent environment row exists. It authenticates with
  `{:api_key, key}`, or with a federated token for the federation `ids`
  (see `Tuist.Sandboxes.Anthropic.Federation.verify/2`). Returns
  `{:error, :not_self_hosted}` for an environment Anthropic runs itself.
  """
  def fetch_anthropic_environment(%Account{}, {:api_key, key}, environment_id) when is_binary(key) do
    {:api_key, key} |> ControlPlane.get_environment(environment_id) |> self_hosted_environment()
  end

  def fetch_anthropic_environment(%Account{id: account_id}, %{} = ids, environment_id) do
    with {:ok, token} <- Federation.verify(account_id, ids) do
      {:bearer, token} |> ControlPlane.get_environment(environment_id) |> self_hosted_environment()
    end
  end

  @doc """
  Connects a Claude Managed Agents self-hosted environment, as the
  dashboard and the `connect_claude_environment` MCP tool do: fetches it
  with `credential` (see `fetch_anthropic_environment/3`), so a wrong
  credential, environment id or workspace fails before anything is stored,
  then creates the row named after the environment. `attrs` carries
  `anthropic_environment_id`, `environment_key`, the credential's own
  attributes (`anthropic_api_key` or the four federation ids) and optionally
  the shape.
  """
  def connect_managed_agents_environment(
        %Account{} = account,
        credential,
        %{anthropic_environment_id: environment_id} = attrs
      ) do
    with {:ok, environment} <- fetch_anthropic_environment(account, credential, environment_id) do
      create_agent_environment(
        account,
        Map.merge(attrs, %{kind: :managed_agents, name: String.slice(environment["name"] || environment_id, 0, 100)})
      )
    end
  end

  defp self_hosted_environment({:ok, %{"config" => %{"type" => "self_hosted"}} = environment}), do: {:ok, environment}
  defp self_hosted_environment({:ok, _environment}), do: {:error, :not_self_hosted}
  defp self_hosted_environment({:error, reason}), do: {:error, reason}

  # ----- Agent sessions -----

  defdelegate start_agent_session(account, attrs, opts \\ []), to: AgentSessions
  defdelegate list_agent_sessions(account), to: AgentSessions
  defdelegate get_agent_session(account, id), to: AgentSessions
  defdelegate get_agent_session!(account, id), to: AgentSessions
  defdelegate refresh_agent_session(agent_session), to: AgentSessions
  defdelegate send_agent_session_message(agent_session, text), to: AgentSessions
  defdelegate list_agent_session_events(agent_session, opts \\ []), to: AgentSessions
  defdelegate archive_agent_session(agent_session), to: AgentSessions

  @doc """
  Deletes the environment and, best effort, every sandbox created for its
  sessions. A sandbox whose node refuses the delete stays behind in the
  error state (with its `agent_environment_id` nilified by the FK) so an
  operator can retry it from the account API.
  """
  def delete_agent_environment(%AgentEnvironment{} = agent_environment) do
    Sandbox
    |> where([s], s.agent_environment_id == ^agent_environment.id)
    |> Repo.all()
    |> Enum.each(fn sandbox ->
      case delete(sandbox) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("sandboxes: failed to delete sandbox while deleting its agent environment",
            sandbox_id: sandbox.id,
            agent_environment_id: agent_environment.id,
            reason: inspect(reason)
          )
      end
    end)

    with {:ok, deleted} <- Repo.delete(agent_environment) do
      reconcile_claude_code(deleted)
      {:ok, deleted}
    end
  end

  # ----- Sandboxes -----

  @doc """
  The account's sandboxes, newest first unless `sort_by:` (`:created`,
  `:last_active` or `:name`) and `sort_order:` say otherwise.

  `search:` keeps those whose id or Amp Orb id contains the text,
  `status: {:== | :!=, status}` filters by the status the dashboard shows
  (`:active`, `:idle`, `:starting`, `:resuming`, `:paused`, `:archived` or
  `:failed`), `vcpus: {:== | :!=, vcpus}` by size, and `limit:` with
  `offset:` reads one page.
  """
  def list_sandboxes(%Account{} = account, opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, :created)
    direction = Keyword.get(opts, :sort_order, :desc)

    query =
      account
      |> filtered_sandboxes(opts)
      |> order_by(^[{direction, sort_field(sort_by)}, {direction, dynamic([s], s.id)}])

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> query |> limit(^limit) |> offset(^Keyword.get(opts, :offset, 0))
      end

    query |> Repo.all() |> preload_creators()
  end

  def preload_creators(sandboxes) do
    usernames = sandboxes |> Enum.map(& &1.amp_creator_username) |> Enum.reject(&is_nil/1) |> Enum.map(&String.downcase/1)
    emails = sandboxes |> Enum.map(& &1.amp_creator_email) |> Enum.reject(&is_nil/1) |> Enum.map(&String.downcase/1)

    # Matching is for display only. Email must be verified on both sides;
    # fallback labels are never interpreted as usernames or email addresses.
    accounts =
      if usernames == [] and emails == [] do
        []
      else
        Repo.all(
          from(a in Account,
            join: u in User,
            on: u.id == a.user_id and u.active == true and is_nil(u.disabled_at),
            where: a.name in ^usernames or (not is_nil(u.email_verified_at) and u.email in ^emails),
            select: %{name: a.name, email: u.email, email_verified_at: u.email_verified_at}
          )
        )
      end

    names = Map.new(accounts, &{String.downcase(&1.name), &1.name})

    email_names =
      accounts
      |> Enum.reject(&is_nil(&1.email_verified_at))
      |> Map.new(&{String.downcase(&1.email), &1.name})

    session_names = session_creator_names(sandboxes)

    Enum.map(sandboxes, &%{&1 | creator_actor: sandbox_creator(&1, names, email_names, session_names)})
  end

  defp session_creator_names(sandboxes) do
    session_sandbox_ids = for s <- sandboxes, is_nil(s.amp_orb_id) and not is_nil(s.anthropic_session_id), do: s.id

    if session_sandbox_ids == [] do
      %{}
    else
      from(s in Sandbox,
        join: session in AgentSession,
        on:
          session.anthropic_session_id == s.anthropic_session_id and session.account_id == s.account_id and
            session.agent_environment_id == s.agent_environment_id,
        join: u in User,
        on: u.id == session.created_by_user_id and u.active == true and is_nil(u.disabled_at),
        join: a in Account,
        on: a.user_id == u.id,
        where: s.id in ^session_sandbox_ids,
        select: {s.id, a.name}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  defp sandbox_creator(sandbox, names, email_names, session_names) do
    matched_name =
      Enum.find_value(
        [
          Map.get(session_names, sandbox.id),
          Map.get(email_names, String.downcase(sandbox.amp_creator_email || "")),
          Map.get(names, String.downcase(sandbox.amp_creator_username || ""))
        ],
        & &1
      )

    name = matched_name || sandbox.amp_creator_name || sandbox.amp_creator_user_id

    %{
      name: name,
      source:
        cond do
          matched_name -> :matched
          name -> :reported
          true -> :unknown
        end
    }
  end

  @doc """
  How many of the account's sandboxes `list_sandboxes/2` would list with
  the same filters, across every page.
  """
  def count_sandboxes(%Account{} = account, opts \\ []) do
    account |> filtered_sandboxes(opts) |> Repo.aggregate(:count)
  end

  defp filtered_sandboxes(%Account{id: account_id}, opts) do
    from(s in Sandbox, where: s.account_id == ^account_id and s.state != ^:deleted and s.purpose == :agent)
    |> where_search(Keyword.get(opts, :search))
    |> where_status(Keyword.get(opts, :status))
    |> where_vcpus(Keyword.get(opts, :vcpus))
  end

  defp where_search(query, search) when search in [nil, ""], do: query

  defp where_search(query, search) do
    pattern = "%" <> String.replace(search, ~r/[\\%_]/, "\\\\\\0") <> "%"

    where(
      query,
      [s],
      ilike(type(s.id, :string), ^pattern) or ilike(s.amp_orb_id, ^pattern) or
        ilike(s.anthropic_session_id, ^pattern)
    )
  end

  defp where_status(query, nil), do: query
  defp where_status(query, {:==, status}), do: where(query, ^status_condition(status))
  defp where_status(query, {:!=, status}), do: where(query, ^dynamic(not (^status_condition(status))))

  defp status_condition(:active), do: dynamic([s], s.state == :running and not is_nil(s.residency_work_id))
  defp status_condition(:idle), do: dynamic([s], s.state == :running and is_nil(s.residency_work_id))
  defp status_condition(:starting), do: dynamic([s], s.state == :creating)
  defp status_condition(:resuming), do: dynamic([s], s.state == :resuming)
  defp status_condition(:paused), do: dynamic([s], s.state == :paused)
  defp status_condition(:archived), do: dynamic([s], s.state == :archived)
  defp status_condition(:failed), do: dynamic([s], s.state == :error)

  defp where_vcpus(query, nil), do: query
  defp where_vcpus(query, {:==, vcpus}), do: where(query, [s], s.vcpus == ^vcpus)
  defp where_vcpus(query, {:!=, vcpus}), do: where(query, [s], s.vcpus != ^vcpus)

  defp sort_field(:last_active), do: dynamic([s], coalesce(s.last_active_at, s.inserted_at))
  defp sort_field(:name), do: dynamic([s], coalesce(s.amp_orb_id, coalesce(s.anthropic_session_id, type(s.id, :string))))
  defp sort_field(:created), do: dynamic([s], s.inserted_at)

  @doc """
  The vCPU sizes of the account's sandboxes, for filtering by size.
  """
  def sandbox_vcpus(%Account{id: account_id}) do
    Repo.all(
      from s in Sandbox,
        where: s.account_id == ^account_id and s.state != ^:deleted and s.purpose == :agent,
        distinct: true,
        order_by: s.vcpus,
        select: s.vcpus
    )
  end

  @doc """
  How many of the account's sandboxes are in each state, with every state
  present.
  """
  def count_sandboxes_by_state(%Account{id: account_id}) do
    counts =
      Repo.all(
        from s in Sandbox,
          where: s.account_id == ^account_id and s.state != ^:deleted and s.purpose == :agent,
          group_by: s.state,
          select: {s.state, count(s.id)}
      )

    Map.merge(Map.new(Sandbox.states() -- [:deleted], &{&1, 0}), Map.new(counts))
  end

  @doc """
  Sandboxes paused, or errored, since before `cutoff`: both still hold
  their disk on the node until deleted. A sandbox the node reported as
  paused without the server pausing it has no `paused_at`; its last
  update stands in.
  """
  def list_sandboxes_idle_before(%DateTime{} = cutoff, orbs \\ :exclude) do
    orb_filter =
      case orbs do
        :exclude -> dynamic([s], is_nil(s.amp_orb_id))
        :macos -> dynamic([s], not is_nil(s.amp_orb_id) and s.platform == :darwin)
      end

    Repo.all(
      from s in Sandbox,
        where: ^orb_filter,
        where: s.purpose == :agent,
        # An archived sandbox was paused too (its disks moved off the node),
        # and keeps that pause's retention.
        where:
          (s.state in [:paused, :archived] and coalesce(s.paused_at, s.updated_at) < ^cutoff) or
            (s.state == :error and s.updated_at < ^cutoff),
        order_by: [asc: s.updated_at]
    )
  end

  @doc """
  Whether an account member who isn't an administrator may use the sandbox:
  one that serves no agent environment, Amp integration, provider environment
  or remote execution, since those hold credentials or other people's work.
  """
  def member_sandbox?(%Sandbox{} = sandbox),
    do:
      is_nil(sandbox.agent_environment_id) and is_nil(sandbox.amp_integration_id) and
        is_nil(sandbox.provider_environment_id) and sandbox.purpose == :agent

  def get_sandbox(%Account{id: account_id}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Sandbox{} = sandbox <- Repo.get_by(Sandbox, id: uuid, account_id: account_id, purpose: :agent) do
      {:ok, sandbox}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_sandbox!(%Account{} = account, id) do
    case get_sandbox(account, id) do
      {:ok, sandbox} -> sandbox
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Sandbox
    end
  end

  def get_sandbox_by_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Sandbox, uuid)
      :error -> nil
    end
  end

  def get_sandbox_for_session(agent_environment_id, session_id)
      when is_integer(agent_environment_id) and is_binary(session_id) do
    Repo.get_by(Sandbox, agent_environment_id: agent_environment_id, anthropic_session_id: session_id)
  end

  @doc """
  Inserts the sandbox row, picks a node that has the template ready and
  boots the VM there. The row exists before the node hears about the id,
  so a report that races the create never looks like an orphan.

  `from_disk_snapshot: %DiskSnapshot{}` clones the snapshot's disks on its
  node instead of booting the template. When that node cannot take the
  sandbox, no longer holds the copy, or the clone fails, an archived
  snapshot is restored from object storage on any node with room; the
  sandbox boots from the template when there is no archive or that fails.
  `id:` gives the sandbox a known id, so a caller that loses the answer
  finds what it created.

  `prefer_nodes:` names nodes a template boot tries first when they have
  room, such as the nodes holding the session repository's checkout
  (`Capacity.place/3`).
  """
  def create_sandbox(%Account{id: account_id}, attrs \\ %{}, opts \\ []) when is_map(attrs) do
    attrs = Map.drop(attrs, [:purpose, "purpose"])

    attrs =
      attrs
      |> platform_defaults()
      |> Map.put(:account_id, account_id)

    changeset = Sandbox.create_changeset(%Sandbox{id: Keyword.get(opts, :id)}, attrs)

    with {:ok, requested} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, sandbox} <- Concurrency.admit(account_id, requested, fn -> Repo.insert(changeset) end) do
      Events.record(sandbox, "created")
      boot(sandbox, Keyword.get(opts, :from_disk_snapshot), Keyword.get(opts, :prefer_nodes, []))
    end
  end

  defp boot(%Sandbox{} = sandbox, source, prefer \\ []) do
    hostname = "sbx-" <> String.slice(sandbox.id, 0, 8)
    started_at = System.monotonic_time(:millisecond)

    args = %{
      sandbox_id: sandbox.id,
      template: sandbox.template,
      vcpus: sandbox.vcpus,
      memory_mb: sandbox.memory_mb,
      workspace_gb: sandbox.workspace_gb,
      hostname: hostname
    }

    case place_and_create(sandbox, args, source, prefer) do
      {:ok, node_name, data} ->
        Logger.info("sandboxes: sandbox created",
          sandbox_id: sandbox.id,
          node: node_name,
          preferred_node: node_name in prefer,
          template: sandbox.template,
          disk_snapshot_id: data["disk_snapshot_id"],
          disk_snapshot_copy: data["disk_snapshot_copy"],
          from_archive: match?({:archive, _}, source),
          boot_ms: data["boot_ms"]
        )

        boot_event = Events.boot(boot_source(source, data), System.monotonic_time(:millisecond) - started_at)

        # Placement recorded the node (and, for macOS, its incarnation) on
        # the row behind this struct.
        result =
          sandbox
          |> Repo.reload!()
          |> update_sandbox(
            %{
              state: :running,
              node_name: node_name,
              resident: sandbox.platform == :darwin,
              hostname: hostname,
              template_tag: data["template_tag"],
              last_active_at: now(),
              error_message: nil
            },
            boot_event
          )
          |> schedule_idle_pause()

        # A sandbox resumed from its archived memory still reads it until its
        # node reports `memory_loaded`.
        with {:ok, running} <- result, {:archive, _source} <- source do
          if data["memory_pending"], do: Archives.memory_loading(running), else: Archives.delete_restored(running)
        end

        result

      # The archive is the only copy of the sandbox, so a failed restore
      # leaves it archived for the next spawn to retry. Placement set
      # `node_name` on the row behind this struct, hence the reload.
      {:error, reason} when is_tuple(source) and elem(source, 0) == :archive ->
        Logger.warning("sandboxes: restoring an archived sandbox failed", sandbox_id: sandbox.id, reason: inspect(reason))

        {:ok, _} =
          sandbox
          |> Repo.reload!()
          |> update_sandbox(%{
            state: :archived,
            node_name: nil,
            hostname: hostname,
            error_message: error_message(reason)
          })

        {:error, reason}

      {:error, reason} ->
        Logger.warning("sandboxes: sandbox creation failed", sandbox_id: sandbox.id, reason: inspect(reason))
        {:ok, _} = update_sandbox(sandbox, %{state: :error, hostname: hostname, error_message: error_message(reason)})
        {:error, reason}
    end
  end

  # A disk snapshot clone that failed fell back to its archive or the template.
  defp boot_source({:archive, _source}, _data), do: "archive"
  defp boot_source(_source, %{"disk_snapshot_archive" => true}), do: "disk_snapshot_archive"
  defp boot_source(_source, %{"disk_snapshot_id" => id}) when is_binary(id), do: "disk_snapshot"
  defp boot_source(_source, %{"warm" => true}), do: "warm"
  defp boot_source(_source, _data), do: "template"

  defp place_and_create(sandbox, args, source, prefer \\ [])

  defp place_and_create(%Sandbox{platform: :darwin} = sandbox, args, nil, _prefer),
    do: create_on_macos_host(sandbox, args, [])

  defp place_and_create(sandbox, args, nil, prefer) do
    placed =
      if prefer == [],
        do: Capacity.place(sandbox),
        else: Capacity.place(sandbox, fn _node -> true end, prefer: prefer)

    with {:ok, node_name} <- placed,
         sandbox = Repo.reload!(sandbox),
         {:ok, data} <- node_call(%{sandbox | node_name: node_name}, "create", args, timeout: @create_timeout) do
      {:ok, node_name, data}
    end
  end

  defp place_and_create(sandbox, args, {:archive, source}, _prefer) do
    with {:ok, node_name} <- place_restore(sandbox),
         {:ok, data} <-
           Nodes.call(node_name, "create", Map.put(args, :from_archive, source), timeout: @restore_timeout) do
      {:ok, node_name, data}
    end
  end

  # A node holding the snapshot (its own, or one it was copied to) clones
  # it fastest, so those go first. When none of them can take the sandbox
  # or the clone fails, an archived snapshot boots from its archive on any
  # node with room, without holding that node's reservation, and is copied
  # out if it is popular; otherwise, or when that fails too, the template
  # boots. A failed clone of a snapshot without an archive keeps the node's
  # reservation, so the template boot retries on the same node.
  defp place_and_create(sandbox, args, %DiskSnapshot{} = disk_snapshot, _prefer) do
    case DiskSnapshots.held_nodes(disk_snapshot) do
      [] -> create_from_disk_snapshot_archive(sandbox, args, disk_snapshot)
      held -> create_from_held_disk_snapshot(sandbox, args, disk_snapshot, held)
    end
  end

  defp create_from_held_disk_snapshot(sandbox, args, disk_snapshot, held) do
    case Capacity.place_on_node(sandbox, held) do
      {:ok, node_name} ->
        clone_args = Map.put(args, :from_disk_snapshot, disk_snapshot.id)

        case Nodes.call(node_name, "create", clone_args, timeout: @create_timeout) do
          {:ok, data} ->
            DiskSnapshots.touch(disk_snapshot, node_name)

            {:ok, node_name,
             Map.merge(data, %{
               "disk_snapshot_id" => disk_snapshot.id,
               "disk_snapshot_copy" => node_name != disk_snapshot.node_name
             })}

          {:error, reason} ->
            Logger.warning("sandboxes: create from disk snapshot failed",
              sandbox_id: sandbox.id,
              disk_snapshot_id: disk_snapshot.id,
              node: node_name,
              reason: inspect(reason)
            )

            DiskSnapshots.forget_if_missing(disk_snapshot, node_name, reason)
            create_after_failed_clone(sandbox, args, node_name, disk_snapshot)
        end

      {:error, reason} ->
        Logger.info("sandboxes: disk snapshot node cannot take the sandbox, booting elsewhere",
          sandbox_id: sandbox.id,
          disk_snapshot_id: disk_snapshot.id,
          node: Enum.join(held, ","),
          reason: inspect(reason)
        )

        create_from_disk_snapshot_archive(sandbox, args, disk_snapshot)
    end
  end

  # A macOS host's own checks (its CI grant, its disk) are final and can
  # refuse a create the server placed, after which the host discards the
  # VM itself. The create moves on to the next host instead of failing.
  defp create_on_macos_host(sandbox, args, refused) do
    placed =
      if refused == [],
        do: Capacity.place(sandbox),
        else: Capacity.place(sandbox, &(&1.name not in refused))

    with {:ok, node_name} <- placed do
      sandbox = Repo.reload!(sandbox)

      case node_call(%{sandbox | node_name: node_name}, "create", args, timeout: @create_timeout) do
        {:ok, data} ->
          {:ok, node_name, data}

        {:error, reason} = error ->
          if host_refused?(reason) do
            Logger.info("sandboxes: macOS host refused the create, trying the next one",
              sandbox_id: sandbox.id,
              node: node_name,
              reason: inspect(reason)
            )

            sandbox |> release_node() |> create_on_macos_host(args, [node_name | refused])
          else
            error
          end
      end
    end
  end

  # A capacity refusal, plain or with the host's reason. One joined with
  # another error (a line break) is not only a refusal.
  defp host_refused?(:no_capacity), do: true
  defp host_refused?("macOS sandbox capacity unavailable: " <> detail), do: not String.contains?(detail, "\n")
  defp host_refused?(_reason), do: false

  defp create_after_failed_clone(sandbox, args, _node_name, %DiskSnapshot{archived_at: %DateTime{}} = disk_snapshot) do
    sandbox |> release_node() |> create_from_disk_snapshot_archive(args, disk_snapshot)
  end

  defp create_after_failed_clone(_sandbox, args, node_name, %DiskSnapshot{}) do
    with {:ok, data} <- Nodes.call(node_name, "create", args, timeout: @create_timeout) do
      {:ok, node_name, data}
    end
  end

  defp create_from_disk_snapshot_archive(sandbox, args, %DiskSnapshot{archived_at: %DateTime{}} = disk_snapshot) do
    with {:ok, source} <- Archives.restore_source(disk_snapshot),
         {:ok, node_name} <- place_restore(sandbox, disk_snapshot) do
      case Nodes.call(node_name, "create", Map.put(args, :from_archive, source), timeout: @restore_timeout) do
        {:ok, data} ->
          DiskSnapshots.touch(disk_snapshot)
          # Every node holding it was full or failed: copy it out ahead of
          # the project's next spawn.
          DiskSnapshots.queue_copies(disk_snapshot)
          {:ok, node_name, Map.merge(data, %{"disk_snapshot_id" => disk_snapshot.id, "disk_snapshot_archive" => true})}

        # The node holds the reservation already, so the template boots there.
        {:error, reason} ->
          Logger.warning("sandboxes: create from a disk snapshot archive failed, booting the template",
            sandbox_id: sandbox.id,
            disk_snapshot_id: disk_snapshot.id,
            node: node_name,
            reason: inspect(reason)
          )

          with {:ok, data} <- Nodes.call(node_name, "create", args, timeout: @create_timeout) do
            {:ok, node_name, data}
          end
      end
    else
      {:error, reason} ->
        Logger.info("sandboxes: no node can create the sandbox from the disk snapshot archive, booting the template",
          sandbox_id: sandbox.id,
          disk_snapshot_id: disk_snapshot.id,
          reason: inspect(reason)
        )

        place_and_create(sandbox, args, nil)
    end
  end

  defp create_from_disk_snapshot_archive(sandbox, args, %DiskSnapshot{}), do: place_and_create(sandbox, args, nil)

  # Gives back the node `Capacity.place_on_node/2` reserved, so the sandbox
  # can be placed anew: the reservation is the row's `node_name`.
  defp release_node(%Sandbox{id: id} = sandbox) do
    Repo.update_all(from(s in Sandbox, where: s.id == ^id), set: [node_name: nil])
    %{sandbox | node_name: nil}
  end

  # An archive in an in-rack store is served over its site's private
  # network, so only nodes at that site can download it. `archive` is the
  # sandbox itself, or the disk snapshot it is created from. An archive with
  # a memory image resumes warm only on a node whose snapshot compatibility
  # matches the one that wrote it, so it waits for room on those, taking the
  # node it was archived from only when no other can; only when none is
  # connected does it cold boot its disks on another.
  defp place_restore(sandbox, archive \\ nil) do
    subject = archive || sandbox
    site = Archives.restore_site(subject)
    on_site = restore_nodes(site, Archives.lazy_disks?(subject))

    case Archives.memory_compat(subject) do
      nil when is_nil(site) -> Capacity.place(sandbox)
      nil -> Capacity.place(sandbox, on_site)
      compat -> place_warm(sandbox, on_site, compat, Archives.origin_nodes(subject))
    end
  end

  # An archive with lazy disks restores only on nodes that read them.
  defp restore_nodes(site, lazy_disks?) do
    fn node ->
      (is_nil(site) or Sites.shard_storage_site(node.name) == site) and
        (not lazy_disks? or Map.get(node, :lazy_disks) == true)
    end
  end

  defp place_warm(sandbox, on_site, compat, origin) do
    case Capacity.place(sandbox, &(on_site.(&1) and Map.get(&1, :snapshot_compat) == compat), avoid: origin) do
      {:error, :no_node} -> Capacity.place(sandbox, on_site)
      placed -> placed
    end
  end

  @doc """
  Runs `fun` while holding the cluster-wide lock of one sandbox, so the
  lifecycle transitions different processes and replicas issue for the
  same sandbox (the next turn's resume, the pause after its grace period,
  a reclaim, an API call) happen one at a time against a fresh row.
  `wait: false` answers `{:error, :locked}` instead of waiting; callers
  that already hold another sandbox's lock must use it, so two of them
  never wait on each other. Never call this from a node's socket process:
  the node commands issued under the lock are answered through it.
  """
  def with_sandbox_lock(sandbox_id, fun, opts \\ []) when is_binary(sandbox_id) and is_function(fun, 0) do
    retries = if Keyword.get(opts, :wait, true), do: :infinity, else: 0

    case :global.trans({{__MODULE__, sandbox_id}, self()}, fun, [node() | Node.list()], retries) do
      :aborted -> {:error, :locked}
      result -> result
    end
  end

  def ensure_running(%Sandbox{state: :running} = sandbox), do: {:ok, sandbox}

  def ensure_running(%Sandbox{state: state, id: id}) when state in [:paused, :archived] do
    with_sandbox_lock(id, fn -> with_fresh(id, &running_or_resume/1) end)
  end

  def ensure_running(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  def resume(%Sandbox{id: id}) do
    with_sandbox_lock(id, fn ->
      with_fresh(id, fn
        %Sandbox{state: state} = sandbox when state in [:paused, :archived] -> running_or_resume(sandbox)
        %Sandbox{state: state} -> {:error, {:invalid_state, state}}
      end)
    end)
  end

  @doc """
  Makes the session's sandbox run and records the residency of `work_id`
  in one step under the sandbox's lock, so a scheduled pause cannot slip
  between the resume and the residency that keeps it running. Pass
  `created: true` when the caller has just created the sandbox.
  """
  def prepare_residency(%Sandbox{id: id}, work_id, opts \\ []) when is_binary(work_id) do
    with_sandbox_lock(id, fn -> with_fresh(id, &prepare_fresh_residency(&1, work_id, opts)) end)
  end

  defp prepare_fresh_residency(sandbox, work_id, opts) do
    admitted? = sandbox.platform == :darwin and (sandbox.state != :running or Keyword.get(opts, :created, false))

    with {:ok, sandbox} <- running_or_resume(sandbox) do
      # A macOS create or resume was just admitted, by the server and
      # under the host's grant check. A grant that closed while the VM
      # booted or restored must not refuse the turn: the VM already holds
      # its slot, and the refusal would only fail the spawn for a retry.
      if admitted?, do: record_residency(sandbox, work_id), else: begin_residency(sandbox, work_id)
    end
  end

  defp with_fresh(id, fun) do
    case get_sandbox_by_id(id) do
      %Sandbox{} = sandbox -> fun.(sandbox)
      nil -> {:error, :not_found}
    end
  end

  defp running_or_resume(%Sandbox{state: :running} = sandbox), do: {:ok, sandbox}

  defp running_or_resume(%Sandbox{state: :paused} = sandbox) do
    case do_resume(sandbox) do
      # Its own node has no room for it (CI filling it or reserving it), and
      # a paused Linux sandbox can only resume there until it is archived:
      # queue that, so a later resume restores it on any node with room. A
      # resume the node admits before the upload ends cancels it.
      {:error, :no_capacity} = error when sandbox.platform == :linux ->
        Archives.move_off(sandbox)
        error

      result ->
        result
    end
  end

  defp running_or_resume(%Sandbox{state: :archived} = sandbox), do: restore(sandbox)
  defp running_or_resume(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  defp do_resume(%Sandbox{state: :paused, node_name: node_name} = sandbox) when is_binary(node_name) do
    started = System.monotonic_time(:millisecond)

    with {:ok, sandbox} <- Capacity.admit(sandbox) do
      admitted = System.monotonic_time(:millisecond)

      case node_call(sandbox, "resume", %{sandbox_id: sandbox.id}, timeout: @resume_timeout) do
        {:ok, data} ->
          Logger.info("sandboxes: sandbox resumed",
            sandbox_id: sandbox.id,
            node: node_name,
            restore_ms: data["restore_ms"],
            admit_ms: admitted - started,
            node_call_ms: System.monotonic_time(:millisecond) - admitted
          )

          sandbox
          |> update_sandbox(%{state: :running, paused_at: nil, last_active_at: now(), error_message: nil})
          |> schedule_idle_pause()

        {:error, :no_capacity} ->
          # CI can revoke the grant after server admission. The host refused
          # the launch, so the checkpoint remains retryable. Keep the residency
          # charge until an authoritative host report confirms its release.
          {:ok, _} = update_sandbox(sandbox, %{state: :paused, error_message: nil})
          {:error, :no_capacity}

        # The snapshot is intact on the node's disk; a node that is away or
        # slow is not a reason to give the sandbox up.
        {:error, reason} when reason in @transient_node_errors ->
          {:ok, _} = update_sandbox(sandbox, %{state: if(sandbox.platform == :darwin, do: :resuming, else: :paused)})
          {:error, reason}

        {:error, reason} ->
          {:ok, _} = update_sandbox(sandbox, %{state: :error, error_message: error_message(reason)})
          {:error, reason}
      end
    end
  end

  defp do_resume(%Sandbox{state: :paused}), do: {:error, :no_node}

  # A restored sandbox runs again, so the restore is admitted against the
  # account's CPU and memory like a create, and then placed on any node with
  # room and cold booted on the archived disks.
  defp restore(%Sandbox{state: :archived} = sandbox) do
    with {:ok, source} <- Archives.restore_source(sandbox),
         {:ok, creating} <-
           Concurrency.admit(sandbox.account_id, sandbox, fn ->
             update_sandbox(sandbox, %{state: :creating, node_name: nil, error_message: nil})
           end) do
      boot(creating, {:archive, source})
    end
  end

  @doc """
  Pauses a running sandbox.
  """
  def pause(%Sandbox{id: id}) do
    with_sandbox_lock(id, fn ->
      with_fresh(id, fn
        %Sandbox{state: :running} = sandbox -> do_pause(sandbox)
        %Sandbox{state: state} -> {:error, {:invalid_state, state}}
      end)
    end)
  end

  @doc """
  Pauses the sandbox only if it is still running with no residency (and,
  with `:residency_epoch`, only if no residency started or ended since
  that epoch), checked against the row under the sandbox's lock. Answers
  `{:ok, :skipped}` when the sandbox is no longer idle. `wait: false`
  skips a sandbox whose lock is held, which is how a reclaim running
  under another sandbox's lock avoids waiting on it.
  """
  def pause_idle(sandbox_id, opts \\ []) when is_binary(sandbox_id) do
    epoch = Keyword.get(opts, :residency_epoch)

    with_sandbox_lock(
      sandbox_id,
      fn ->
        with_fresh(sandbox_id, fn
          %Sandbox{state: :running, residency_work_id: nil} = sandbox
          when is_nil(epoch) or sandbox.residency_epoch == epoch ->
            # An agent turn can take over the residency of running commands;
            # the commands still keep the sandbox up when that turn ends.
            if commands_running?(sandbox), do: {:ok, :skipped}, else: do_pause(sandbox)

          %Sandbox{} ->
            {:ok, :skipped}
        end)
      end,
      wait: Keyword.get(opts, :wait, true)
    )
  end

  defp commands_running?(%Sandbox{id: id}) do
    Repo.exists?(from(c in Tuist.Sandboxes.SandboxCommand, where: c.sandbox_id == ^id and c.status == :running))
  end

  # Every pause flushes the guest's page cache first: an archive or disk
  # snapshot keeps only the disks, and the node refuses either one after a
  # pause that did not sync.
  defp do_pause(%Sandbox{state: :running, node_name: node_name} = sandbox) when is_binary(node_name) do
    case node_call(sandbox, "pause", %{sandbox_id: sandbox.id, sync_disks: true}, []) do
      {:ok, data} ->
        Logger.info("sandboxes: sandbox paused",
          sandbox_id: sandbox.id,
          node: node_name,
          snapshot_ms: data["snapshot_ms"],
          mem_bytes: data["mem_bytes"],
          disks_synced: data["disks_synced"]
        )

        # Commit the pause and residency release together. The caller can die
        # after this write; no follow-up request is needed to make it idle.
        query =
          from(s in Sandbox,
            where:
              s.id == ^sandbox.id and s.state in [:running, :paused] and s.residency_epoch == ^sandbox.residency_epoch,
            select: s
          )

        case Repo.update_all(query,
               set: [
                 state: :paused,
                 paused_at: now(),
                 residency_work_id: nil,
                 guest_cpu_ms: nil,
                 resident: data["resident"] == true,
                 updated_at: now()
               ],
               inc: [residency_epoch: 1]
             ) do
          {1, [paused]} ->
            Events.record_transition(sandbox, paused)
            if Capacity.shared_node?(node_name), do: Capacity.enqueue_reclaim(node_name)
            {:ok, paused}

          {0, []} ->
            # The socket may already have recorded this pause from a report.
            with_fresh(sandbox.id, fn
              %Sandbox{state: :paused, residency_work_id: nil} = paused -> {:ok, paused}
              _ -> {:error, :not_running}
            end)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_pause(%Sandbox{state: :running}), do: {:error, :no_node}

  @doc """
  Refreshes an unsynced paused checkpoint before archiving, through normal
  resume admission. A new turn or lifecycle change since the failed archive
  wins. Keep its original pause age so the next archive pass can retry.
  """
  def sync_paused_disks(%Sandbox{} = expected) do
    with_sandbox_lock(expected.id, fn ->
      with_fresh(expected.id, fn
        %Sandbox{state: :paused, residency_work_id: nil} = sandbox
        when sandbox.node_name == expected.node_name and sandbox.residency_epoch == expected.residency_epoch and
               sandbox.paused_at == expected.paused_at ->
          with {:ok, running} <- do_resume(sandbox),
               {:ok, paused} <- do_pause(running) do
            update_sandbox(paused, %{paused_at: expected.paused_at})
          end

        _ ->
          {:ok, :skipped}
      end)
    end)
  end

  @doc """
  Tears the VM down on its node and removes the row. An archived
  sandbox's archive object is deleted with it. The row flips to
  `deleted` first so a concurrent report ignores it, and a node that is
  not connected does not block the delete: the orphaned jail directory
  is removed when the node's next report lists a sandbox we no longer
  know.
  """
  def delete(%Sandbox{id: id} = sandbox) do
    with_sandbox_lock(id, fn ->
      sandbox = get_sandbox_by_id(id) || sandbox

      with {:ok, sandbox} <- update_sandbox(sandbox, %{state: :deleted, residency_work_id: nil}),
           :ok <- delete_on_node(sandbox),
           :ok <- Archives.delete_object(sandbox) do
        with {:ok, deleted} <- Repo.delete(sandbox) do
          Events.record(deleted, "deleted")
          {:ok, deleted}
        end
      else
        {:error, reason} ->
          {:ok, _} = update_sandbox(sandbox, %{state: :error, error_message: error_message(reason)})
          {:error, reason}
      end
    end)
  end

  defp delete_on_node(%Sandbox{node_name: nil}), do: :ok

  defp delete_on_node(%Sandbox{} = sandbox) do
    case node_call(sandbox, "delete", %{sandbox_id: sandbox.id}, []) do
      {:ok, _data} -> :ok
      {:error, :not_connected} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs `cmd` (an argv list) inside the sandbox, resuming it first when it
  is paused, and returns the exit code with the collected output. Output
  is capped at 1 MiB per stream.

  Options: `:timeout_ms` (default 60s, max 10min), `:env`, `:cwd`.
  """
  def exec(%Sandbox{} = sandbox, cmd, opts \\ []) when is_list(cmd) do
    timeout_ms =
      opts
      |> Keyword.get(:timeout_ms, @exec_default_timeout_ms)
      |> max(1)
      |> min(@exec_max_timeout_ms)

    case ensure_exec_capacity(sandbox) do
      {:ok, %Sandbox{node_name: node_name} = sandbox} when is_binary(node_name) ->
        opts = Keyword.put(opts, :timeout_ms, timeout_ms)

        result =
          case run_exec(sandbox, cmd, opts) do
            {:error, reason} = result ->
              if interrupted_by_pause?(reason), do: exec_after_pause(sandbox, cmd, opts), else: result

            result ->
              result
          end

        record_activity(sandbox)
        result

      {:ok, %Sandbox{}} ->
        {:error, :no_node}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A sandbox on a shared node is paused as soon as it is idle
  # (`schedule_pause/1`), and its row says running until the node's snapshot
  # is done, so an exec can reach the node mid-pause. The pause holds the
  # sandbox's lock: wait for it, resume the sandbox and run the command once
  # more.
  defp exec_after_pause(%Sandbox{} = sandbox, cmd, opts) do
    case await_pause(sandbox) do
      {:ok, %Sandbox{node_name: node_name} = sandbox} when is_binary(node_name) -> run_exec(sandbox, cmd, opts)
      {:ok, %Sandbox{}} -> {:error, :no_node}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Whether the node refused work because the sandbox is pausing or paused
  while the row still says running.
  """
  def interrupted_by_pause?("sandbox is being paused" <> _), do: true
  def interrupted_by_pause?("sandbox is not running: " <> rest), do: String.ends_with?(rest, " is paused")
  def interrupted_by_pause?(_reason), do: false

  @doc """
  Waits for a pause the node has started while the row still says running
  (the pause holds the sandbox's lock), then answers the sandbox running,
  resuming it when the pause went through.
  """
  def await_pause(%Sandbox{id: id}) do
    with_sandbox_lock(id, fn ->
      with_fresh(id, fn
        %Sandbox{state: :running} = sandbox -> settle_running(sandbox)
        sandbox -> running_or_resume(sandbox)
      end)
    end)
  end

  # A pause whose caller died, such as a web pod stopped by a deploy, leaves
  # the VM paused while the row says running until reports settle it, and
  # every command until then fails. Every pause and resume takes the lock this
  # runs under, so the node's answer now is the sandbox's state: adopt its
  # pause and resume.
  defp settle_running(%Sandbox{} = sandbox) do
    with {:error, "sandbox is not running: " <> _ = reason} <- exec_running(sandbox, ["true"], timeout_ms: 10_000),
         true <- interrupted_by_pause?(reason),
         {:ok, paused} <- adopt_node_pause(sandbox) do
      running_or_resume(paused)
    else
      _ -> {:ok, sandbox}
    end
  end

  defp adopt_node_pause(%Sandbox{} = sandbox) do
    query =
      from(s in Sandbox,
        where: s.id == ^sandbox.id and s.state == :running and s.residency_epoch == ^sandbox.residency_epoch,
        select: s
      )

    case Repo.update_all(query,
           set: [state: :paused, paused_at: now(), residency_work_id: nil, guest_cpu_ms: nil, updated_at: now()],
           inc: [residency_epoch: 1]
         ) do
      {1, [paused]} ->
        Logger.info("sandboxes: adopted a pause the node made", sandbox_id: sandbox.id, node: sandbox.node_name)
        Events.record_transition(sandbox, paused)
        {:ok, paused}

      {0, []} ->
        :error
    end
  end

  @doc """
  Runs `cmd` in a sandbox that is already running, without resuming it,
  admitting a turn or counting as activity: for the server's own short
  reads of the guest, such as before a pause.
  """
  def exec_running(sandbox, cmd, opts \\ [])

  def exec_running(%Sandbox{state: :running, node_name: node_name} = sandbox, cmd, opts)
      when is_binary(node_name) and is_list(cmd) do
    run_exec(sandbox, cmd, Keyword.update(opts, :timeout_ms, @exec_default_timeout_ms, &min(&1, @exec_max_timeout_ms)))
  end

  def exec_running(%Sandbox{}, _cmd, _opts), do: {:error, :not_running}

  defp run_exec(%Sandbox{} = sandbox, cmd, opts) do
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)

    args = %{
      sandbox_id: sandbox.id,
      cmd: cmd,
      env: Keyword.get(opts, :env, %{}),
      cwd: Keyword.get(opts, :cwd, workspace(sandbox)),
      timeout_ms: timeout_ms
    }

    ref = make_ref()
    caller = self()
    on_stream = fn {stream, data} -> capture_output(caller, ref, stream, data) end

    result =
      node_call(sandbox, "exec", args, timeout: timeout_ms + @exec_timeout_slack_ms, on_stream: on_stream)

    {stdout, stderr} = drain_output(ref)
    {stdout, stderr} = if Keyword.get(opts, :raw_output), do: {stdout, stderr}, else: {utf8(stdout), utf8(stderr)}
    Process.delete({ref, :stdout})
    Process.delete({ref, :stderr})

    case result do
      {:ok, data} when is_map(data) -> {:ok, %{exit_code: data["exit_code"], stdout: stdout, stderr: stderr}}
      {:ok, _data} -> {:ok, %{exit_code: nil, stdout: stdout, stderr: stderr}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_exec_capacity(sandbox) do
    with {:ok, running} <- ensure_running(sandbox) do
      if running.residency_work_id,
        do: {:ok, running},
        else: Capacity.admit_turn(running, fn -> {:ok, running} end)
    end
  end

  # `on_stream` runs in the calling process for every frame, so the cap
  # is applied there, before anything reaches the mailbox: output past
  # the limit is dropped as it arrives instead of piling up until the
  # call returns.
  defp capture_output(caller, ref, stream, data) do
    key = {ref, stream}
    size = Process.get(key, 0)
    room = @exec_output_limit_bytes - size

    if room > 0 do
      chunk = if byte_size(data) > room, do: binary_part(data, 0, room), else: data
      Process.put(key, size + byte_size(chunk))
      send(caller, {ref, stream, chunk})
    end
  end

  # Everything for `ref` is already queued once the call returns, so a
  # non-blocking drain collects it all. Output is bytes; the API returns
  # strings, so unless the caller asks for `raw_output`, invalid UTF-8
  # (binary output, or a cut through a multi-byte character) is replaced.
  defp drain_output(ref, stdout \\ [], stderr \\ []) do
    receive do
      {^ref, :stdout, data} -> drain_output(ref, [stdout, data], stderr)
      {^ref, :stderr, data} -> drain_output(ref, stdout, [stderr, data])
    after
      0 -> {IO.iodata_to_binary(stdout), IO.iodata_to_binary(stderr)}
    end
  end

  defp utf8(output), do: String.replace_invalid(output)

  @doc """
  Starts the sandbox's worker. `checkout`, a repository checkout volume the
  server allocated for the session (`Tuist.Runners.CacheVolumes`), lets the
  node start the worker from its master of the repository.
  """
  def start_worker(sandbox, env, checkout \\ nil)

  def start_worker(%Sandbox{state: :running, node_name: node_name} = sandbox, env, checkout)
      when is_binary(node_name) and is_map(env) do
    args = %{sandbox_id: sandbox.id, env: env}
    node_call(sandbox, "start_worker", if(checkout, do: Map.put(args, :checkout, checkout), else: args), [])
  end

  def start_worker(%Sandbox{state: :running}, _env, _checkout), do: {:error, :no_node}
  def start_worker(%Sandbox{state: state}, _env, _checkout), do: {:error, {:invalid_state, state}}

  def stop_worker(%Sandbox{state: :running, node_name: node_name} = sandbox) when is_binary(node_name) do
    node_call(sandbox, "stop_worker", %{sandbox_id: sandbox.id}, [])
  end

  def stop_worker(%Sandbox{state: :running}), do: {:error, :no_node}
  def stop_worker(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  # ----- Residencies -----

  defdelegate update_allocation(params), to: Capacity

  @doc """
  Records the residency of `work_id` on a running sandbox. The epoch is
  incremented in SQL so a residency ending concurrently (its
  `worker_exited` arrives on the node's socket process) never loses an
  increment.
  """
  def begin_residency(%Sandbox{} = sandbox, work_id) when is_binary(work_id) do
    Capacity.admit_turn(sandbox, fn -> record_residency(sandbox, work_id) end)
  end

  defp record_residency(%Sandbox{id: id}, work_id) do
    timestamp = now()

    query = from(s in Sandbox, where: s.id == ^id and s.state == :running, select: s)

    case Repo.update_all(query,
           set: [residency_work_id: work_id, last_active_at: timestamp, updated_at: timestamp],
           inc: [residency_epoch: 1]
         ) do
      {1, [sandbox]} -> {:ok, sandbox}
      {0, []} -> {:error, :not_running}
    end
  end

  @doc """
  Records `work_id` as the residency of a running sandbox, under the same
  admission as a turn, when the sandbox has none; answers the sandbox as is
  when `work_id` already holds it, so several users can share one residency
  (`Tuist.Sandboxes.Commands`). Answers `{:error, :busy}` when another
  residency, such as an agent turn or an Orb, holds the sandbox.
  """
  def begin_shared_residency(%Sandbox{id: id} = sandbox, work_id) when is_binary(work_id) do
    timestamp = now()
    held = from(s in Sandbox, where: s.id == ^id and s.state == :running and s.residency_work_id == ^work_id, select: s)

    # Joining a residency that already holds the sandbox needs no admission:
    # the sandbox's memory is already counted.
    case Repo.update_all(held, set: [last_active_at: timestamp, updated_at: timestamp]) do
      {1, [sandbox]} -> {:ok, sandbox}
      {0, []} -> admit_shared_residency(sandbox, work_id)
    end
  end

  defp admit_shared_residency(%Sandbox{id: id} = sandbox, work_id) do
    Capacity.admit_turn(sandbox, fn ->
      timestamp = now()

      query =
        from(s in Sandbox, where: s.id == ^id and s.state == :running and is_nil(s.residency_work_id), select: s)

      case Repo.update_all(query,
             set: [residency_work_id: work_id, last_active_at: timestamp, updated_at: timestamp],
             inc: [residency_epoch: 1]
           ) do
        {1, [sandbox]} ->
          {:ok, sandbox}

        {0, []} ->
          case Repo.get(Sandbox, id) do
            %Sandbox{state: :running, residency_work_id: ^work_id} = sandbox -> {:ok, sandbox}
            %Sandbox{state: :running} -> {:error, :busy}
            %Sandbox{state: state} -> {:error, {:invalid_state, state}}
            nil -> {:error, :not_found}
          end
      end
    end)
  end

  @doc """
  Ends the residency only while `work_id` still holds it, then schedules the
  idle pause as `end_residency/1` does. A late call for an earlier residency
  leaves a newer one alone.
  """
  def end_residency(sandbox_id, work_id) when is_binary(sandbox_id) and is_binary(work_id) do
    timestamp = now()
    query = from(s in Sandbox, where: s.id == ^sandbox_id and s.residency_work_id == ^work_id, select: s)

    case Repo.update_all(query,
           set: [residency_work_id: nil, last_active_at: timestamp, updated_at: timestamp],
           inc: [residency_epoch: 1]
         ) do
      {1, [%Sandbox{state: :running} = updated]} ->
        with {:ok, _job} <- schedule_pause(updated, work_id), do: {:ok, updated}

      {1, [updated]} ->
        {:ok, updated}

      {0, []} ->
        :ok
    end
  end

  @doc """
  Makes the sandbox run and records the shared residency `work_id`
  (`begin_shared_residency/2`) in one step under the sandbox's lock, so an
  idle pause scheduled by the resume or create cannot slip in between.
  """
  def prepare_shared_residency(%Sandbox{id: id}, work_id) when is_binary(work_id) do
    with_sandbox_lock(id, fn ->
      with_fresh(id, fn sandbox ->
        with {:ok, running} <- running_or_resume(sandbox), do: begin_shared_residency(running, work_id)
      end)
    end)
  end

  @doc """
  Tells a macOS host that detached guest work (an Amp Orb's turn) holds the
  running VM, so its idle eviction waits for the pause that ends the turn.
  With `hold_ms`, the host ends the hold that long after this call unless
  it is held again; without it, only a release or pause ends it. Linux
  nodes keep no host-side residency; the server's row is enough there.
  """
  def hold_host_residency(sandbox, work_id, hold_ms \\ nil)

  def hold_host_residency(%Sandbox{platform: :darwin} = sandbox, work_id, hold_ms) when is_binary(work_id) do
    args = maybe_put(%{sandbox_id: sandbox.id, work_id: work_id}, :hold_ms, hold_ms)

    with {:ok, _data} <- node_call(sandbox, "hold_residency", args, []),
         do: :ok
  end

  def hold_host_residency(%Sandbox{}, _work_id, _hold_ms), do: :ok

  def release_host_residency(%Sandbox{platform: :darwin, node_name: node_name} = sandbox, work_id)
      when is_binary(node_name) and is_binary(work_id) do
    with {:ok, _data} <- node_call(sandbox, "release_residency", %{sandbox_id: sandbox.id, work_id: work_id}, []),
         do: :ok
  end

  def release_host_residency(%Sandbox{}, _work_id), do: :ok

  @doc """
  Clears the residency, bumps the epoch and schedules the pause that
  follows the grace period. The bump is what lets the scheduled job
  recognise that a newer residency started after it was enqueued.
  """
  def end_residency(%Sandbox{id: id} = sandbox) do
    timestamp = now()
    query = from(s in Sandbox, where: s.id == ^id and s.state != :deleted, select: s)

    query =
      if sandbox.platform == :darwin, do: where(query, [s], s.residency_epoch == ^sandbox.residency_epoch), else: query

    case Repo.update_all(query,
           set: [residency_work_id: nil, last_active_at: timestamp, updated_at: timestamp],
           inc: [residency_epoch: 1]
         ) do
      {1, [updated]} ->
        with {:ok, _job} <- schedule_pause(updated), do: {:ok, updated}

      {0, []} ->
        {:ok, sandbox}
    end
  end

  # A sandbox left running without a residency (created or resumed
  # through the API, or used by an exec) is paused once it has been idle
  # for the grace period, as one is after a residency ends. Each new use
  # replaces the pending pause, and a residency starting meanwhile bumps
  # the epoch, which turns the pending pause into a no-op.
  defp schedule_idle_pause({:ok, %Sandbox{} = sandbox}) do
    schedule_idle_pause(sandbox)
    {:ok, sandbox}
  end

  defp schedule_idle_pause({:error, _reason} = error), do: error

  defp schedule_idle_pause(%Sandbox{state: :running, residency_work_id: nil} = sandbox) do
    case schedule_pause(sandbox) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: could not schedule the idle pause", sandbox_id: sandbox.id, reason: inspect(reason))
        :ok
    end
  end

  defp schedule_idle_pause(%Sandbox{}), do: :ok

  defp record_activity(%Sandbox{id: id}) do
    timestamp = now()
    query = from(s in Sandbox, where: s.id == ^id and s.state == :running, select: s)

    case Repo.update_all(query, set: [last_active_at: timestamp, updated_at: timestamp]) do
      {1, [sandbox]} -> schedule_idle_pause(sandbox)
      {0, []} -> :ok
    end
  end

  defp schedule_pause(%Sandbox{} = sandbox, ended_residency \\ nil) do
    %{sandbox_id: sandbox.id, residency_epoch: sandbox.residency_epoch}
    |> PauseSandboxWorker.new(
      schedule_in: pause_delay_seconds(sandbox, ended_residency),
      replace: [scheduled: [:args, :scheduled_at], available: [:args, :scheduled_at]]
    )
    |> Oban.insert()
  end

  # Hosts shared with CI get their memory back at once, except after the
  # last command ends on Linux: commands come in runs, such as a sync and
  # then a build, and a command started while its sandbox pauses waits for
  # the pause and a resume. CI pressure pauses an idle sandbox before its
  # grace is up. A macOS sandbox's commands residency already outlived its
  # last command by the session lease (`Tuist.Sandboxes.Commands`).
  defp pause_delay_seconds(%Sandbox{} = sandbox, ended_residency) do
    cond do
      not (sandbox.platform == :darwin or Capacity.shared_node?(sandbox.node_name)) -> pause_grace_seconds(sandbox)
      ended_residency == Commands.residency() and sandbox.platform != :darwin -> @shared_command_pause_grace_seconds
      true -> 0
    end
  end

  defp pause_grace_seconds(%Sandbox{agent_environment_id: nil}), do: @default_pause_grace_seconds

  defp pause_grace_seconds(%Sandbox{agent_environment_id: agent_environment_id}) do
    case Repo.get(AgentEnvironment, agent_environment_id) do
      %AgentEnvironment{pause_grace_seconds: seconds} when is_integer(seconds) -> seconds
      _ -> @default_pause_grace_seconds
    end
  end

  # ----- Node events and reports -----

  def handle_node_event(node_name, %{"event" => "worker_exited", "sandbox_id" => sandbox_id} = event) do
    case get_sandbox_by_id(sandbox_id) do
      %Sandbox{state: state} = sandbox when state != :deleted ->
        Logger.info("sandboxes: worker exited",
          sandbox_id: sandbox.id,
          node: node_name,
          exit_code: event["exit_code"],
          duration_ms: event["duration_ms"]
        )

        if sandbox.platform != :darwin or
             (sandbox.node_name == node_name and sandbox.node_uid == event["generation"] and
                sandbox.residency_work_id == event["work_id"]) do
          {:ok, _sandbox} = end_residency(sandbox)
        end

        :ok

      _ ->
        :ok
    end
  end

  def handle_node_event(node_name, %{"event" => "sandbox_died", "sandbox_id" => sandbox_id} = event) do
    case get_sandbox_by_id(sandbox_id) do
      %Sandbox{state: state} = sandbox when state != :deleted ->
        Logger.warning("sandboxes: sandbox died", sandbox_id: sandbox.id, node: node_name, reason: event["reason"])

        if sandbox.platform != :darwin or (sandbox.node_name == node_name and sandbox.node_uid == event["generation"]) do
          error_or_revert(sandbox, event["reason"] || "sandbox died")
        end

        :ok

      _ ->
        :ok
    end
  end

  def handle_node_event(node_name, %{"event" => "memory_loaded", "sandbox_id" => sandbox_id}) do
    case get_sandbox_by_id(sandbox_id) do
      %Sandbox{node_name: ^node_name} = sandbox ->
        Logger.info("sandboxes: restored memory loaded", sandbox_id: sandbox.id, node: node_name)
        Archives.memory_loaded(sandbox)
        :ok

      _ ->
        :ok
    end
  end

  def handle_node_event(node_name, %{"event" => "template_ready"} = event) do
    Logger.info("sandboxes: template ready", node: node_name, template: event["name"], tag: event["tag"])
    :ok
  end

  def handle_node_event(node_name, event) do
    Logger.warning("sandboxes: unknown node event", node: node_name, node_event: inspect(event))
    :ok
  end

  @doc """
  Aligns the database with a node's `hello` or `report`. Sandboxes the
  node lists take its node name and state (an `error` it reports marks
  the row errored); sandboxes we believe live on the node but it does not
  list are marked as errored; sandboxes the node lists that we no longer
  know are deleted from the node. A row left `creating` or `resuming` by a
  caller that died mid-operation is settled from the report once it has
  been stuck longer than any create or resume can take.
  Disk snapshots are reconciled the same way (`DiskSnapshots.reconcile_node_report/2`).
  """
  def reconcile_node_report(node_name, %{"sandboxes" => reported} = report)
      when is_binary(node_name) and is_list(reported) do
    :ok = DiskSnapshots.reconcile_node_report(node_name, report)

    reported_by_id =
      Map.new(
        for %{"id" => id} = sandbox <- reported,
            {:ok, uuid} <- [Ecto.UUID.cast(id)],
            do: {uuid, sandbox}
      )

    reported_ids = Map.keys(reported_by_id)
    known = Repo.all(from s in Sandbox, where: s.id in ^reported_ids)

    Enum.each(known, fn sandbox ->
      reconcile_known_report(sandbox, node_name, report["generation"], Map.fetch!(reported_by_id, sandbox.id))
    end)

    reported_ids
    |> Kernel.--(Enum.map(known, & &1.id))
    |> Enum.each(&delete_orphan(node_name, &1))

    reconcile_missing(node_name, reported_ids, report["generation"])
  end

  def reconcile_node_report(_node_name, _report), do: :ok

  @doc """
  Releases the Linux sandboxes of nodes that left the cluster: a node that
  is not connected and whose Kubernetes Node is gone took its VMs and disks
  with it, so no report will ever settle their rows. A running row would
  otherwise keep refusing turns as if its node were full and keep charging
  the account's quota; a paused one could never resume. Each row becomes
  `error` with no node, which spawns and session routers replace with a
  fresh sandbox; an interrupted restore goes back to its archive. Any other
  answer from Kubernetes (an unreachable API, a server outside a cluster)
  leaves the rows alone. macOS hosts are virtual Nodes that can deregister
  and come back with their VMs, so their rows are left to recovery.
  """
  def release_removed_nodes do
    from(s in Sandbox,
      where:
        s.platform == :linux and s.purpose == :agent and not is_nil(s.node_name) and
          s.state in ^[:creating, :resuming, :running, :paused, :error],
      distinct: true,
      select: s.node_name
    )
    |> Repo.all()
    |> Enum.reject(&Nodes.connected?/1)
    |> Enum.filter(&(KubernetesClient.get_node(&1, timeout: 5_000) == {:error, :not_found}))
    |> Enum.each(&release_removed_node/1)
  end

  defp release_removed_node(node_name) do
    from(s in Sandbox, where: s.node_name == ^node_name and s.platform == :linux and s.purpose == :agent)
    |> where([s], s.state in ^[:creating, :resuming, :running, :paused, :error])
    |> Repo.all()
    |> Enum.each(fn sandbox ->
      Logger.warning("sandboxes: releasing a sandbox whose node left the cluster",
        sandbox_id: sandbox.id,
        node: node_name,
        state: sandbox.state
      )

      if sandbox.state == :creating and sandbox.archived_at do
        Archives.revert_restore(sandbox.id)
      else
        {released, _} =
          Repo.update_all(
            from(s in Sandbox, where: s.id == ^sandbox.id and s.node_name == ^node_name and s.state == ^sandbox.state),
            set: [
              state: :error,
              node_name: nil,
              error_message: "node left the cluster",
              residency_work_id: nil,
              updated_at: now()
            ],
            inc: [residency_epoch: 1]
          )

        if released == 1 and sandbox.state != :error, do: Events.record(sandbox, "failed")
      end
    end)
  end

  defp reconcile_missing(node_name, reported_ids, generation) do
    stuck_before = DateTime.add(now(), -@stuck_after_seconds, :second)
    # A node builds a report before sending it, so one can arrive just after
    # a create or resume it predates and not list that sandbox. Only a row
    # unchanged for two report intervals is missing; a later report settles it.
    settled_before = DateTime.add(now(), -@report_settle_seconds, :second)

    Sandbox
    |> where([s], s.node_name == ^node_name and s.id not in ^reported_ids and s.purpose == :agent)
    |> where(
      [s],
      (s.state in ^[:running, :paused, :resuming] and s.updated_at < ^settled_before) or
        (s.state == :creating and s.updated_at < ^stuck_before)
    )
    |> Repo.all()
    |> Enum.each(fn sandbox ->
      Logger.warning("sandboxes: sandbox missing on node", sandbox_id: sandbox.id, node: node_name, state: sandbox.state)

      if sandbox.platform != :darwin or sandbox.node_uid == generation do
        error_or_revert(sandbox, "missing on node", sandbox.state)
      end
    end)

    :ok
  end

  defp reconcile_known_report(sandbox, node_name, generation, reported) do
    if sandbox.platform != :darwin or (sandbox.node_name == node_name and sandbox.node_uid == generation) do
      reconcile_reported(sandbox, node_name, reported)

      if sandbox.platform == :darwin and is_binary(sandbox.residency_work_id) and
           reported["finished_work_id"] == sandbox.residency_work_id do
        end_residency(sandbox)
      end
    end
  end

  defp reconcile_reported(%Sandbox{state: :deleted}, _node_name, _reported), do: :ok

  # Execution VMs are tracked by their scheduler and lease, not node reports.
  defp reconcile_reported(%Sandbox{purpose: :remote_execution}, _node_name, _reported), do: :ok

  # Archiving deletes the jail after the row is archived; a node that missed
  # that delete still lists it.
  defp reconcile_reported(%Sandbox{state: :archived, id: id}, node_name, _reported), do: delete_orphan(node_name, id)

  # A paused copy left on a former node is not evidence that the current
  # node stopped the VM. In particular it cannot release a new residency.
  defp reconcile_reported(%Sandbox{node_name: assigned}, node_name, %{"state" => "paused"})
       when not is_nil(assigned) and assigned != node_name, do: :ok

  defp reconcile_reported(%Sandbox{} = sandbox, _node_name, %{"state" => "error"} = reported) do
    if sandbox.platform == :darwin and is_boolean(reported["resident"]) do
      Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id and s.node_uid == ^sandbox.node_uid),
        set: [resident: reported["resident"]]
      )
    end

    if sandbox.state != :error do
      Logger.warning("sandboxes: node reports sandbox in error", sandbox_id: sandbox.id, reason: reported["error"])
      error_or_revert(sandbox, reported["error"] || "error on the node", sandbox.state)
    end

    :ok
  end

  defp reconcile_reported(%Sandbox{} = sandbox, node_name, reported) do
    attrs =
      %{node_name: node_name}
      |> maybe_put(:resident, reported["resident"])
      |> maybe_put(:template_tag, reported["template_tag"])
      |> maybe_put_state(reported["state"])
      |> keep_in_flight_state(sandbox, reported["state"])
      |> put_reported_pause(sandbox)
      |> put_guest_activity(sandbox, reported)

    if Enum.any?(attrs, fn {key, value} -> Map.get(sandbox, key) != value end) do
      apply_report(sandbox, attrs)
    end

    if idle_orb?(sandbox, attrs), do: enqueue_idle_orb_pause(sandbox)

    :ok
  end

  # Reports run on the socket, which cannot take the lifecycle lock.
  # Never let a report read before a resume, delete or new turn overwrite
  # it, even when both writes land within the same timestamp second.
  defp apply_report(sandbox, attrs) do
    query =
      from(s in Sandbox,
        where:
          s.id == ^sandbox.id and s.state == ^sandbox.state and s.residency_epoch == ^sandbox.residency_epoch and
            s.updated_at == ^sandbox.updated_at,
        select: s
      )

    updates = [set: Map.to_list(Map.put(attrs, :updated_at, now()))]

    updates =
      if attrs[:state] == :paused and (sandbox.state != :paused or not is_nil(sandbox.residency_work_id)),
        do: Keyword.put(updates, :inc, residency_epoch: 1),
        else: updates

    case Repo.update_all(query, updates) do
      {1, [updated]} -> Events.record_transition(sandbox, updated)
      {0, []} -> :ok
    end
  end

  # A daemon shutdown (or a pause whose caller lost the result) can leave
  # the VM paused without a server pause. Repeated reports also heal old
  # paused rows, without continually moving their archive age forward.
  defp put_reported_pause(%{state: :paused} = attrs, sandbox) do
    paused_at = if sandbox.state == :paused, do: sandbox.paused_at || now(), else: now()
    Map.merge(attrs, %{paused_at: paused_at, residency_work_id: nil, guest_cpu_ms: nil})
  end

  defp put_reported_pause(%{state: :running} = attrs, _sandbox), do: Map.put(attrs, :paused_at, nil)
  defp put_reported_pause(attrs, _sandbox), do: attrs

  # A running guest is active when it used more than @active_cpu_ms_per_second
  # of CPU since the last report that found it active. A smaller reading
  # than that one comes from a new VM process.
  defp put_guest_activity(attrs, %Sandbox{state: :running} = sandbox, %{"state" => "running", "cpu_ms" => cpu_ms})
       when is_integer(cpu_ms) do
    if guest_active?(sandbox, cpu_ms),
      do: Map.merge(attrs, %{guest_cpu_ms: cpu_ms, last_active_at: now()}),
      else: attrs
  end

  defp put_guest_activity(attrs, _sandbox, _reported), do: attrs

  defp guest_active?(%Sandbox{guest_cpu_ms: last, last_active_at: %DateTime{} = since}, cpu_ms) when is_integer(last) do
    cpu_ms < last or cpu_ms - last > DateTime.diff(now(), since, :second) * @active_cpu_ms_per_second
  end

  defp guest_active?(%Sandbox{}, _cpu_ms), do: true

  # Amp pauses an Orb when its thread goes idle. A running Orb whose guest
  # stayed quiet for @orb_idle_pause_after_seconds is paused here in case
  # that pause never arrives.
  defp idle_orb?(%Sandbox{state: :running, amp_orb_id: orb_id, guest_cpu_ms: cpu_ms} = sandbox, attrs)
       when is_binary(orb_id) and is_integer(cpu_ms) do
    Map.get(attrs, :state) == :running and not Map.has_key?(attrs, :guest_cpu_ms) and
      is_struct(sandbox.last_active_at, DateTime) and
      DateTime.diff(now(), sandbox.last_active_at, :second) >= @orb_idle_pause_after_seconds
  end

  defp idle_orb?(_sandbox, _attrs), do: false

  defp enqueue_idle_orb_pause(%Sandbox{} = sandbox) do
    %{sandbox_id: sandbox.id, last_active_at: DateTime.to_iso8601(sandbox.last_active_at)}
    |> PauseIdleOrbWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: could not schedule the idle Orb pause",
          sandbox_id: sandbox.id,
          reason: inspect(reason)
        )
    end
  end

  # A resume in flight holds its memory reservation through `resuming`, and
  # the node lists the sandbox as paused until the restore completes, so
  # that report must not release the reservation early, unless the resume
  # has been stuck longer than one can take (its caller died). A node that
  # already reports the sandbox running settles it either way.
  defp keep_in_flight_state(attrs, %Sandbox{state: :resuming} = sandbox, "paused") do
    if stuck?(sandbox), do: attrs, else: Map.drop(attrs, [:state, :error_message])
  end

  defp keep_in_flight_state(attrs, %Sandbox{state: :creating} = sandbox, reported_state)
       when reported_state != "running" do
    if stuck?(sandbox), do: attrs, else: Map.drop(attrs, [:state, :error_message])
  end

  # A report captured before a pause or resume finished can arrive after its
  # result. Let a later report confirm an opposing state before adopting it.
  defp keep_in_flight_state(attrs, %Sandbox{state: state} = sandbox, reported_state)
       when (state == :running and reported_state == "paused") or (state == :paused and reported_state == "running") do
    if DateTime.diff(now(), sandbox.updated_at, :second) > @report_settle_seconds,
      do: attrs,
      else: Map.drop(attrs, [:state, :error_message])
  end

  defp keep_in_flight_state(attrs, _sandbox, _reported_state), do: attrs

  defp stuck?(%Sandbox{updated_at: updated_at}) do
    DateTime.diff(now(), updated_at, :second) > @stuck_after_seconds
  end

  # A restore that fails on the node leaves the sandbox archived: its archive
  # is still the only copy.
  defp error_or_revert(sandbox, message, from_state \\ nil)

  defp error_or_revert(%Sandbox{state: :creating, archived_at: %DateTime{}} = sandbox, _message, _from_state),
    do: Archives.revert_restore(sandbox.id)

  defp error_or_revert(%Sandbox{} = sandbox, message, from_state) do
    if mark_error(sandbox.id, message, from_state) == 1 and sandbox.state != :error, do: Events.record(sandbox, "failed")

    :ok
  end

  # Errors a sandbox from outside its lock (the node's socket process must
  # never wait on one), so it only applies when the row is still in the
  # state it was read in, and the epoch is incremented in SQL.
  defp mark_error(id, message, from_state) do
    query =
      then(from(s in Sandbox, where: s.id == ^id and s.state != :deleted), fn query ->
        if from_state, do: where(query, [s], s.state == ^from_state), else: query
      end)

    {count, _} =
      Repo.update_all(query,
        set: [state: :error, error_message: message, residency_work_id: nil, updated_at: now()],
        inc: [residency_epoch: 1]
      )

    count
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp maybe_put_state(attrs, "running"), do: Map.merge(attrs, %{state: :running, error_message: nil})
  defp maybe_put_state(attrs, "paused"), do: Map.merge(attrs, %{state: :paused, error_message: nil})
  defp maybe_put_state(attrs, _state), do: attrs

  # Runs off the socket process: `Nodes.call/4` blocks on a message the
  # socket itself has to deliver, so calling it inline would deadlock.
  defp delete_orphan(node_name, sandbox_id) do
    Logger.warning("sandboxes: deleting sandbox unknown to the server", sandbox_id: sandbox_id, node: node_name)

    Tasks.run_async(fn ->
      case Nodes.call(node_name, "delete", orphan_args(node_name, sandbox_id), []) do
        {:ok, _data} ->
          :ok

        {:error, reason} ->
          Logger.warning("sandboxes: failed to delete orphaned sandbox",
            sandbox_id: sandbox_id,
            node: node_name,
            reason: inspect(reason)
          )
      end
    end)
  end

  # ----- Helpers -----

  defp update_sandbox(%Sandbox{} = sandbox, attrs, event_attrs \\ %{}) do
    with {:ok, updated} <- sandbox |> Sandbox.update_changeset(attrs) |> Repo.update() do
      Events.record_transition(sandbox, updated, event_attrs)
      {:ok, updated}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(:no_node), do: "no node with the template ready is connected"
  defp error_message(:no_capacity), do: "no node has memory or disk left for the sandbox"
  defp error_message(:locked), do: "another operation on the sandbox is in progress"
  defp error_message(:not_connected), do: "node is not connected"
  defp error_message(:node_disconnected), do: "node disconnected during the operation"
  defp error_message(:timeout), do: "node did not answer in time"
  defp error_message(reason), do: inspect(reason)

  defp node_call(sandbox, op, args, opts) do
    args = if sandbox.platform == :darwin, do: Map.put(args, :node_uid, sandbox.node_uid), else: args

    case Nodes.call(sandbox.node_name, op, args, opts) do
      # This exact native sentinel means admission refused the operation.
      # Joined cleanup/fencing errors must remain failures, not retryable
      # capacity denials. This also works with already-deployed host versions.
      {:error, "macOS sandbox capacity unavailable"} when sandbox.platform == :darwin -> {:error, :no_capacity}
      result -> result
    end
  end

  defp orphan_args(node_name, sandbox_id) do
    case Nodes.lookup(node_name) do
      {:ok, _pid, %{platform: "darwin", generation: generation}} -> %{sandbox_id: sandbox_id, node_uid: generation}
      _ -> %{sandbox_id: sandbox_id}
    end
  end
end
