defmodule Condukt.AgentRuntime do
  @moduledoc """
  Behaviour for runtimes that own an agent's inner execution loop.

  Native Condukt agents use `Condukt.AgentRuntimes.Native`, where
  `Condukt.Session` drives ReqLLM turns and Condukt tool calls. Runtime modules
  that implement this behaviour receive the user prompt, a Condukt-owned
  context map, and per-run options. Durable guidance is passed through the
  composed `:system_prompt` value, including project instructions when enabled.
  They return either a final text response or an explicit result map.
  """

  @callback run(String.t(), map(), keyword()) :: {:ok, String.t() | map()} | {:error, term()}
end
