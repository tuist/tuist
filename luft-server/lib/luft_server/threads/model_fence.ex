defmodule LuftServer.Threads.ModelFence do
  @moduledoc """
  Links the otherwise unlinked Condukt model task to its run worker and fences
  each buffered dispatch. Already dispatched inference can still incur usage;
  database effects and journal writes retain their separate epoch fences.
  """
  @behaviour Plug

  import Plug.Conn

  alias LuftServer.Threads

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    worker = Keyword.fetch!(opts, :worker)
    Process.link(worker)
    send(worker, {:thread_model_process, self()})
    fence = {Keyword.fetch!(opts, :run_id), Keyword.fetch!(opts, :attempt), worker}
    conn = put_private(conn, :thread_model_fence, fence)

    if authorized?(conn) do
      dispatch(conn, Keyword.fetch!(opts, :inner))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        409,
        Jason.encode!(%{
          error: %{message: "This attempt no longer owns the run.", type: "fenced"}
        })
      )
    end
  end

  def authorized?(%{private: %{thread_model_fence: {id, attempt, worker}}}),
    do: Process.alive?(worker) and Threads.owns_run?(id, attempt)

  def authorized?(_), do: false

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
