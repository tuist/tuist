defmodule Tuist.Readiness.Plug do
  @moduledoc """
  Serves `GET /ready` from `Tuist.Readiness.check/1` for the current pod
  role: 200 when every dependency is reachable, 503 otherwise. The body
  names each check and its outcome but not the failure reason, which is
  logged instead.
  """

  @behaviour Plug

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.Readiness

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["ready"]} = conn, opts) do
    checks = Keyword.get_lazy(opts, :checks, fn -> Readiness.checks(Environment.mode()) end)

    {status, results} = Readiness.check(checks)

    body =
      JSON.encode!(%{
        status: status,
        checks: Map.new(results, fn {name, result} -> {name, if(result == :ok, do: "ok", else: "error")} end)
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(if(status == :ok, do: 200, else: 503), body)
  end

  def call(conn, _opts), do: send_resp(conn, 404, "")
end
