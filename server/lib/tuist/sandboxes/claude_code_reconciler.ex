defmodule Tuist.Sandboxes.ClaudeCodeReconciler do
  @moduledoc """
  Converges the Claude Code orchestrator workloads (`Tuist.Sandboxes.ClaudeCodeRuntime`)
  with the enabled `:claude_code` agent environments of accounts with sandboxes:
  every minute, and right after an environment is connected or removed.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 30, states: [:available, :scheduled, :retryable]]

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ClaudeCodeRuntime

  @impl Oban.Worker
  def perform(_job) do
    config = Environment.claude_code_provider_config()
    if is_binary(config.image) and is_binary(config.url), do: reconcile(config), else: :ok
  end

  def reconcile(config) do
    desired =
      :claude_code
      |> Sandboxes.list_enabled_agent_environments()
      |> Enum.filter(&FeatureFlags.sandboxes_enabled?(&1.account))

    names = MapSet.new(desired, &ClaudeCodeRuntime.name/1)

    with :ok <- ensure_all(desired, config),
         {:ok, items} <- ClaudeCodeRuntime.resources(config) do
      Enum.reduce_while(items, :ok, fn %{"metadata" => %{"name" => name}}, :ok ->
        result = if MapSet.member?(names, name), do: :ok, else: ClaudeCodeRuntime.remove(config.namespace, name)
        if result == :ok, do: {:cont, :ok}, else: {:halt, result}
      end)
    end
  end

  defp ensure_all(agent_environments, config) do
    Enum.reduce_while(agent_environments, :ok, fn agent_environment, :ok ->
      case ClaudeCodeRuntime.ensure(agent_environment, config) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
