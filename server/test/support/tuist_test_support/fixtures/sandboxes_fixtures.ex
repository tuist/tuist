defmodule TuistTestSupport.Fixtures.SandboxesFixtures do
  @moduledoc false

  alias Tuist.Repo
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.AgentSession
  alias Tuist.Sandboxes.Sandbox
  alias TuistTestSupport.Fixtures.AccountsFixtures

  def agent_environment_fixture(opts \\ []) do
    account = Keyword.get_lazy(opts, :account, fn -> AccountsFixtures.account_fixture() end)

    attrs = %{
      account_id: account.id,
      anthropic_environment_id:
        Keyword.get(opts, :anthropic_environment_id, "env_#{TuistTestSupport.Utilities.unique_integer()}"),
      environment_key: Keyword.get(opts, :environment_key, "sk-ant-env-#{TuistTestSupport.Utilities.unique_integer()}"),
      anthropic_api_key: Keyword.get(opts, :anthropic_api_key),
      agent_model: Keyword.get(opts, :agent_model, "claude-sonnet-5"),
      agent_system_prompt: Keyword.get(opts, :agent_system_prompt),
      name: Keyword.get(opts, :name, "environment"),
      template: Keyword.get(opts, :template, "default"),
      vcpus: Keyword.get(opts, :vcpus, 2),
      memory_mb: Keyword.get(opts, :memory_mb, 4096),
      workspace_gb: Keyword.get(opts, :workspace_gb, 10),
      max_idle_seconds: Keyword.get(opts, :max_idle_seconds, 30),
      pause_grace_seconds: Keyword.get(opts, :pause_grace_seconds, 30),
      enabled: Keyword.get(opts, :enabled, true)
    }

    %AgentEnvironment{}
    |> AgentEnvironment.create_changeset(attrs)
    |> AgentEnvironment.cache_agent_changeset(Keyword.get(opts, :anthropic_agent_id))
    |> Repo.insert!()
  end

  def agent_session_fixture(opts \\ []) do
    account = Keyword.get_lazy(opts, :account, fn -> AccountsFixtures.account_fixture() end)

    agent_environment =
      Keyword.get_lazy(opts, :agent_environment, fn ->
        agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api-fixture")
      end)

    Repo.insert!(%AgentSession{
      account_id: account.id,
      agent_environment_id: agent_environment.id,
      anthropic_session_id:
        Keyword.get(opts, :anthropic_session_id, "sesn_#{TuistTestSupport.Utilities.unique_integer()}"),
      anthropic_agent_id: Keyword.get(opts, :anthropic_agent_id, "agent_fixture"),
      sandbox_id: Keyword.get(opts, :sandbox_id),
      title: Keyword.get(opts, :title, "Fix the build"),
      prompt: Keyword.get(opts, :prompt, "Fix the build and open a pull request."),
      repository_url: Keyword.get(opts, :repository_url),
      repository_ref: Keyword.get(opts, :repository_ref),
      model: Keyword.get(opts, :model, "claude-sonnet-5"),
      budget_cents: Keyword.get(opts, :budget_cents),
      last_status: Keyword.get(opts, :last_status, "running"),
      last_stop_reason: Keyword.get(opts, :last_stop_reason),
      created_by_user_id: Keyword.get(opts, :created_by_user_id)
    })
  end

  def sandbox_fixture(opts \\ []) do
    account = Keyword.get_lazy(opts, :account, fn -> AccountsFixtures.account_fixture() end)

    Repo.insert!(%Sandbox{
      account_id: account.id,
      agent_environment_id: Keyword.get(opts, :agent_environment_id),
      anthropic_session_id: Keyword.get(opts, :anthropic_session_id),
      template: Keyword.get(opts, :template, "default"),
      template_tag: Keyword.get(opts, :template_tag, "sha-abc"),
      vcpus: Keyword.get(opts, :vcpus, 2),
      memory_mb: Keyword.get(opts, :memory_mb, 4096),
      workspace_gb: Keyword.get(opts, :workspace_gb, 10),
      state: Keyword.get(opts, :state, :running),
      node_name: Keyword.get(opts, :node_name, "node-#{TuistTestSupport.Utilities.unique_integer()}"),
      hostname: Keyword.get(opts, :hostname, "sbx-fixture"),
      residency_work_id: Keyword.get(opts, :residency_work_id),
      residency_epoch: Keyword.get(opts, :residency_epoch, 0),
      last_active_at: opts |> Keyword.get(:last_active_at) |> truncate(),
      paused_at: opts |> Keyword.get(:paused_at) |> truncate(),
      error_message: Keyword.get(opts, :error_message)
    })
  end

  defp truncate(nil), do: nil
  defp truncate(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
end
