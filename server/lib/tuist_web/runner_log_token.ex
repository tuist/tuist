defmodule TuistWeb.RunnerLogToken do
  @moduledoc """
  Signs and verifies the short-lived token that scopes a runner's
  log uploads to a single workflow_job.

  The dispatch endpoint hands this token to the polling Pod alongside
  the JIT config; the in-VM/in-Pod log shipper presents it on every
  `POST /api/internal/runners/logs`. Verification is local
  (`Phoenix.Token`, signed with the endpoint's secret) so the
  high-frequency log path never round-trips the Kubernetes
  `TokenReview` API, and the token keeps authenticating after the
  Postgres claim is deleted at completion — so the runner's final
  flush still lands.

  The payload carries `workflow_job_id` + `account_id`; the ingest
  endpoint attributes lines from the token, never from client-supplied
  fields, so a Pod can't write into another job's stream.
  """
  @salt "runner_job_logs"

  # A runner job can't outlive the 6h billing max-lifetime, so a
  # token older than that can't belong to a live job.
  @max_age_seconds 6 * 60 * 60

  def sign(workflow_job_id, account_id) when is_integer(workflow_job_id) and is_integer(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, @salt, %{workflow_job_id: workflow_job_id, account_id: account_id})
  end

  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(TuistWeb.Endpoint, @salt, token, max_age: @max_age_seconds) do
      {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}}
      when is_integer(workflow_job_id) and is_integer(account_id) ->
        {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}}

      _ ->
        {:error, :invalid_token}
    end
  end

  def verify(_), do: {:error, :invalid_token}
end
