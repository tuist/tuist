defmodule TuistOps.Paging.IRMClient do
  @moduledoc """
  Pages an on-call team through Grafana IRM's direct paging
  (`POST /api/v1/escalation/`). Escalates to the team in `IRM_TEAM_ID`
  with `important_team_escalation: true`, so the team's Direct Paging
  integration can route it to its important escalation chain.

  `IRM_API_URL` is the stack's OnCall API URL (IRM → Settings → API
  tokens), and `IRM_API_TOKEN` an IRM API token, which acts as the
  user who created it and needs the direct-paging permission.
  """

  alias TuistOps.Environment

  def escalate(%{title: title, message: message, source_url: source_url}) do
    with {:ok, api_url} <- fetch(Environment.irm_api_url(), :irm_api_url),
         {:ok, token} <- fetch(Environment.irm_api_token(), :irm_api_token),
         {:ok, team_id} <- fetch(Environment.irm_team_id(), :irm_team_id) do
      (String.trim_trailing(api_url, "/") <> "/api/v1/escalation/")
      |> Req.post(
        headers: [{"authorization", token}],
        json: %{
          title: title,
          message: message,
          source_url: source_url,
          team: team_id,
          important_team_escalation: true
        },
        retry: false,
        receive_timeout: 15_000
      )
      |> handle_response()
    end
  end

  defp fetch(value, _name) when is_binary(value) and value != "", do: {:ok, value}
  defp fetch(_value, name), do: {:error, {:not_configured, name}}

  defp handle_response({:ok, %Req.Response{status: status, body: %{"id" => id}}})
       when status in 200..299,
       do: {:ok, id}

  defp handle_response({:ok, %Req.Response{status: status}}) when status in 200..299,
    do: {:ok, nil}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_status, status, body}}

  defp handle_response({:error, reason}), do: {:error, {:http_error, reason}}
end
