defmodule Tuist.Runners.InteractiveShellBroker do
  @moduledoc false

  alias Phoenix.PubSub

  @pubsub Tuist.PubSub

  def subscribe_client(session_id) when is_integer(session_id) do
    PubSub.subscribe(@pubsub, client_topic(session_id))
  end

  def subscribe_runner(session_id) when is_integer(session_id) do
    PubSub.subscribe(@pubsub, runner_topic(session_id))
  end

  def broadcast_to_client(session_id, message) when is_integer(session_id) do
    PubSub.broadcast(@pubsub, client_topic(session_id), {:runner_shell, message})
  end

  def broadcast_to_runner(session_id, message) when is_integer(session_id) do
    PubSub.broadcast(@pubsub, runner_topic(session_id), {:runner_shell, message})
  end

  defp client_topic(session_id), do: "runner_shell:#{session_id}:client"
  defp runner_topic(session_id), do: "runner_shell:#{session_id}:runner"
end
