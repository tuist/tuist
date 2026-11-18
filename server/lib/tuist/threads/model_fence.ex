defmodule Tuist.Threads.ModelFence do
  @moduledoc """
  Links Condukt's unlinked model task to its worker and fences every dispatch.
  An already dispatched request may still incur usage; ownership checking is
  not atomic with takeover. Tools, replies and checkpoints need their own fences.
  Use buffered Condukt.run, not the streaming transport that bypasses Req plugs.
  """

  @behaviour Plug

  import Plug.Conn

  alias Tuist.Threads

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    worker = Keyword.fetch!(opts, :worker)
    # Link even if the worker has just died: an unlinked orphan must not infer.
    Process.link(worker)
    send(worker, {:thread_model_process, self()})
    fence = {Keyword.fetch!(opts, :run_id), Keyword.fetch!(opts, :attempt), worker}

    conn = put_private(conn, :thread_model_fence, fence)

    if authorized?(conn) do
      dispatch(conn, Keyword.fetch!(opts, :inner))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(409, JSON.encode!(%{error: %{message: "This run attempt no longer owns the run.", type: "fenced"}}))
    end
  end

  @doc "Rechecks ownership immediately before each upstream call."
  def authorized?(%{private: %{thread_model_fence: {id, attempt, worker}}}) do
    Process.alive?(worker) and Threads.owns_run?(id, attempt)
  end

  def authorized?(_conn), do: false

  def wrap(client_opts, %{id: id, attempt: attempt}, worker) do
    Keyword.update!(client_opts, :llm_request_options, fn request_opts ->
      Keyword.update!(request_opts, :req_http_options, fn http_opts ->
        Keyword.update!(http_opts, :plug, fn inner ->
          {__MODULE__, run_id: id, attempt: attempt, worker: worker, inner: inner}
        end)
      end)
    end)
  end

  defp dispatch(conn, fun) when is_function(fun, 1), do: fun.(conn)
  defp dispatch(conn, {module, opts}), do: module.call(conn, module.init(opts))
  defp dispatch(conn, module) when is_atom(module), do: module.call(conn, module.init([]))
end
