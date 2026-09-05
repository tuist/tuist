defmodule Tuist.Sandboxes.Router do
  @moduledoc """
  Routes an acknowledged Anthropic work item to the sandbox of its
  session: finds or creates the sandbox, resumes it when paused, records
  the residency and starts `sbx-worker` inside the VM with the session's
  credentials. Any failure releases the work item with a forced stop so
  Anthropic re-queues it on the session's next event.

  The residency that creates a sandbox also stages the repository the
  agent session asked for under `/workspace` and binds the sandbox to the
  `Tuist.Sandboxes.AgentSession` row.
  """

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.GitHub
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.AgentSession
  alias Tuist.Sandboxes.AgentSessions
  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.VCS

  require Logger

  @git "/usr/bin/git"
  @clone_timeout_ms 90_000
  @checkout_timeout_ms 60_000
  @commit_sha ~r/\A[0-9a-f]{7,64}\z/

  def dispatch(%AgentEnvironment{} = agent_environment, %{"id" => work_id, "data" => %{"id" => session_id}} = item)
      when is_binary(work_id) and is_binary(session_id) do
    with {:ok, sandbox} <- find_or_create_sandbox(agent_environment, session_id, item),
         {:ok, sandbox} <- Sandboxes.ensure_running(sandbox),
         {:ok, sandbox} <- Sandboxes.begin_residency(sandbox, work_id),
         {:ok, _data} <- start_worker(sandbox, worker_env(agent_environment, item, session_id)) do
      Logger.info("sandboxes: worker started",
        sandbox_id: sandbox.id,
        node: sandbox.node_name,
        agent_environment_id: agent_environment.id,
        session_id: session_id,
        work_id: work_id
      )

      :ok
    else
      {:error, reason} ->
        Logger.error("sandboxes: failed to route work item",
          agent_environment_id: agent_environment.id,
          session_id: session_id,
          work_id: work_id,
          reason: inspect(reason)
        )

        release(agent_environment, work_id)
        {:error, reason}
    end
  end

  def dispatch(%AgentEnvironment{} = agent_environment, %{"id" => work_id}) when is_binary(work_id) do
    Logger.error("sandboxes: work item has no session", agent_environment_id: agent_environment.id, work_id: work_id)
    release(agent_environment, work_id)
    {:error, :malformed_work_item}
  end

  defp find_or_create_sandbox(agent_environment, session_id, item) do
    case Sandboxes.get_sandbox_for_session(agent_environment.id, session_id) do
      %Sandbox{state: state} = sandbox when state in [:running, :paused, :creating] ->
        {:ok, sandbox}

      # A sandbox that died or was deleted from under us cannot be
      # resumed; drop what is left of it and start the session afresh.
      %Sandbox{} = sandbox ->
        with {:ok, _deleted} <- Sandboxes.delete(sandbox) do
          create_sandbox(agent_environment, session_id, item)
        end

      nil ->
        create_sandbox(agent_environment, session_id, item)
    end
  end

  defp create_sandbox(agent_environment, session_id, item) do
    with {:ok, account} <- Accounts.get_account_by_id(agent_environment.account_id),
         {:ok, sandbox} <-
           Sandboxes.create_sandbox(account, %{
             agent_environment_id: agent_environment.id,
             anthropic_session_id: session_id,
             template: agent_environment.template,
             vcpus: agent_environment.vcpus,
             memory_mb: agent_environment.memory_mb,
             workspace_gb: agent_environment.workspace_gb
           }) do
      prepare_workspace(account, sandbox, session_id, item)
      {:ok, sandbox}
    end
  end

  # Runs once per sandbox, on the residency that created it. A failed
  # clone is logged and the worker still starts, so the agent can retry
  # from inside the VM.
  defp prepare_workspace(account, sandbox, session_id, item) do
    agent_session = AgentSessions.get_agent_session_by_anthropic_session_id(session_id)

    if agent_session do
      {:ok, _bound} = AgentSessions.bind_sandbox(agent_session, sandbox)
    end

    case repository(agent_session, item) do
      {url, ref} when is_binary(url) -> clone_repository(account, sandbox, url, ref)
      _none -> :ok
    end
  end

  defp repository(%AgentSession{repository_url: url, repository_ref: ref}, _item) when is_binary(url) and url != "" do
    {url, blank_to_nil(ref)}
  end

  defp repository(_agent_session, item) do
    metadata = get_in(item, ["data", "metadata"]) || item["metadata"] || %{}
    {blank_to_nil(metadata["repository_url"]), blank_to_nil(metadata["repository_ref"])}
  end

  defp clone_repository(account, sandbox, url, ref) do
    destination = "/workspace/" <> repository_name(url)
    clone_url = authenticated_url(account, url)
    sha = if is_binary(ref) and Regex.match?(@commit_sha, ref), do: ref
    branch = if is_binary(ref) and is_nil(sha), do: ["--branch", ref], else: []
    clone = [@git, "clone", "--filter=blob:none"] ++ branch ++ [clone_url, destination]
    checkout = if sha, do: [@git, "-C", destination, "checkout", sha]

    with :ok <- run_git(sandbox, clone, @clone_timeout_ms, "clone", url, clone_url),
         :ok <- if(checkout, do: run_git(sandbox, checkout, @checkout_timeout_ms, "checkout", url, clone_url), else: :ok) do
      Logger.info("sandboxes: repository staged", sandbox_id: sandbox.id, repository_url: url, ref: ref)
    end

    :ok
  end

  # `secret_url` never reaches the logs: git can echo the URL it was given
  # in its error output, so the output is redacted before logging.
  defp run_git(sandbox, cmd, timeout_ms, step, url, secret_url) do
    case Sandboxes.exec(sandbox, cmd, timeout_ms: timeout_ms, env: %{"GIT_TERMINAL_PROMPT" => "0"}) do
      {:ok, %{exit_code: 0}} ->
        :ok

      {:ok, %{exit_code: exit_code, stderr: stderr}} ->
        Logger.warning("sandboxes: repository #{step} failed",
          sandbox_id: sandbox.id,
          repository_url: url,
          exit_code: exit_code,
          stderr: stderr |> String.replace(secret_url, url) |> String.slice(-2000, 2000)
        )

        :error

      {:error, reason} ->
        Logger.warning("sandboxes: repository #{step} failed",
          sandbox_id: sandbox.id,
          repository_url: url,
          reason: inspect(reason)
        )

        :error
    end
  end

  # Private github.com repositories are cloned with the account's GitHub
  # App installation token; without an installation the clone is anonymous.
  defp authenticated_url(account, url) do
    with %URI{scheme: "https", host: "github.com", path: path} when is_binary(path) <- URI.parse(url),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id),
         {:ok, %{token: token}} when is_binary(token) <- GitHub.App.get_installation_token(installation, []) do
      "https://x-access-token:" <> token <> "@github.com" <> path
    else
      _ -> url
    end
  end

  defp repository_name(url) do
    name =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> Kernel.||("")
      |> Path.basename()
      |> String.replace_suffix(".git", "")

    if name in ["", "/", "."], do: "repository", else: name
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp start_worker(sandbox, env) do
    case Sandboxes.start_worker(sandbox, env) do
      {:ok, _data} = ok ->
        ok

      {:error, reason} ->
        _ = Sandboxes.end_residency(sandbox)
        {:error, reason}
    end
  end

  defp release(agent_environment, work_id) do
    case Client.stop(agent_environment.anthropic_environment_id, agent_environment.environment_key, work_id, true) do
      {:ok, _stopped} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to release work item",
          agent_environment_id: agent_environment.id,
          work_id: work_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp worker_env(agent_environment, item, session_id) do
    env = %{
      "ANTHROPIC_SESSION_ID" => session_id,
      "ANTHROPIC_WORK_ID" => item["id"],
      "ANTHROPIC_ENVIRONMENT_ID" => agent_environment.anthropic_environment_id,
      "ANTHROPIC_ENVIRONMENT_KEY" => agent_environment.environment_key,
      "ANTHROPIC_WORK_SECRET" => item["secret"] || "",
      "SBX_MAX_IDLE" => "#{agent_environment.max_idle_seconds}s"
    }

    case Environment.anthropic_api_url_override() do
      nil -> env
      base_url -> Map.put(env, "ANTHROPIC_BASE_URL", base_url)
    end
  end
end
