defmodule Atlas.Conversations.ModelFence do
  @moduledoc """
  Req plug wrapped around every model request a conversation run makes.

  Condukt 1.13 executes a session's run in an unlinked `Task.start`, so killing
  the session does not stop a model loop already in progress, and Condukt has no
  API to reach that process. The model request is the one point that always runs
  inside it. Before each request this plug:

    * links the calling process to the run's worker, so the loop dies with the
      worker, and reports it so the worker can kill it on cancel or fencing;
    * refuses the request unless the attempt still owns the run and the run was
      not cancelled, so a superseded or stopped loop cannot make another model
      call.

  This prevents a superseded or stopped attempt from starting further model
  requests; tool calls, checkpoints, and replies are fenced separately, so it
  cannot write state beside its successor. It is not exactly-once inference: a
  request already dispatched to the provider can still finish and incur usage,
  and the ownership check is not atomic with a lease takeover that happens
  while the request is in flight.
  """

  @behaviour Plug

  import Ecto.Query
  import Plug.Conn

  alias Atlas.Conversations.Run
  alias Atlas.Repo

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    worker = Keyword.fetch!(opts, :worker)

    if Process.alive?(worker) do
      Process.link(worker)
      send(worker, {:conversation_model_process, self()})
    end

    if owns_run?(Keyword.fetch!(opts, :run_id), Keyword.fetch!(opts, :attempt)) do
      dispatch(conn, Keyword.fetch!(opts, :inner))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(409, JSON.encode!(%{error: %{message: "This run attempt no longer owns the run.", type: "fenced"}}))
    end
  end

  defp owns_run?(run_id, attempt) do
    Repo.exists?(
      from run in Run,
        where:
          run.id == ^run_id and run.status == "running" and run.resume_count == ^attempt and
            is_nil(run.cancel_requested_at)
    )
  end

  defp dispatch(conn, fun) when is_function(fun, 1), do: fun.(conn)
  defp dispatch(conn, {module, opts}), do: module.call(conn, module.init(opts))
  defp dispatch(conn, module) when is_atom(module), do: module.call(conn, module.init([]))

  @doc """
  Wraps the plug in `client_opts` with the fence for one run attempt.

  Conversation client options always route model requests through a Req plug
  (`Runner.profile_client_opts/2` uses the in-process relay). Options without
  one raise instead of producing an unfenced run.
  """
  def wrap(client_opts, %Run{id: run_id, resume_count: attempt}, worker) do
    Keyword.update!(client_opts, :llm_request_options, fn request_options ->
      Keyword.update!(request_options, :req_http_options, fn http_options ->
        Keyword.update!(http_options, :plug, fn inner ->
          {__MODULE__, run_id: run_id, attempt: attempt, worker: worker, inner: inner}
        end)
      end)
    end)
  end
end
