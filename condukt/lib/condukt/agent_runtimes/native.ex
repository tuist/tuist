defmodule Condukt.AgentRuntimes.Native do
  @moduledoc """
  Marker module for the built-in Condukt agent loop.

  With this runtime, `Condukt.Session` owns each ReqLLM turn, native tool call,
  compaction, and message history update.
  """
end
