defmodule Condukt.Operation.SubmitTool do
  @moduledoc false

  use Condukt.Tool

  @impl Condukt.Tool
  def name(_opts), do: "submit_result"

  @impl Condukt.Tool
  def description(_opts) do
    "Submit your final structured result for the current operation. Call exactly once when you are done, then stop."
  end

  @impl Condukt.Tool
  def parameters(opts), do: Keyword.fetch!(opts, :schema)

  @impl Condukt.Tool
  def call(args, %{opts: opts}) do
    reply_to = Keyword.fetch!(opts, :reply_to)
    ref = Keyword.fetch!(opts, :ref)
    send(reply_to, {ref, :operation_submit, args})
    {:ok, "Submitted."}
  end
end
