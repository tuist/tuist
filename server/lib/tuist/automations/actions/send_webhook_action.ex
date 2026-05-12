defmodule Tuist.Automations.Actions.SendWebhookAction do
  @moduledoc """
  Automation action that POSTs a Stripe-style event envelope to one of the
  account's configured webhook endpoints.

  The action stores only `webhook_endpoint_id`; the URL and signing secret
  live on the account-scoped `Tuist.Webhooks.WebhookEndpoint` so they can be
  reused across automations. Execution is asynchronous: this action enqueues
  a `Tuist.Webhooks.Workers.DeliveryWorker` Oban job carrying the endpoint id
  and returns `:ok`. The worker re-reads the endpoint at delivery time so
  rotations and updates take effect on the next retry, and a deleted
  endpoint is treated as a permanent failure rather than retried forever.

  A cross-account guard rejects deliveries where the endpoint's account
  doesn't own the alert's project — defence in depth against a forged
  endpoint id slipping past the UI.
  """
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Webhooks
  alias Tuist.Webhooks.Workers.DeliveryWorker

  require Logger

  def execute(automation, %{type: :test_case, id: test_case_id}, action) do
    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         {:ok, endpoint_id} <- fetch_endpoint_id(action, automation),
         {:ok, endpoint} <- Webhooks.get_endpoint(endpoint_id),
         :ok <- authorize_endpoint(endpoint, automation) do
      payload = envelope(automation, endpoint, test_case)
      enqueue(endpoint, payload)
    else
      {:error, :not_found} ->
        Logger.warning(
          "Automation #{automation.id} send_webhook skipped for test case #{test_case_id}: test case or endpoint not found"
        )

        :ok

      {:error, :missing_endpoint_id} ->
        Logger.warning("Automation #{automation.id} send_webhook skipped: action is missing webhook_endpoint_id")

        :ok

      {:error, :cross_account} ->
        Logger.warning(
          "Automation #{automation.id} send_webhook skipped: webhook endpoint belongs to a different account"
        )

        :ok

      other ->
        Logger.warning(
          "Automation #{automation.id} send_webhook skipped for test case #{test_case_id}: #{inspect(other)}"
        )

        :ok
    end
  end

  defp fetch_endpoint_id(%{"webhook_endpoint_id" => id}, _automation) when is_binary(id) and id != "", do: {:ok, id}
  defp fetch_endpoint_id(_action, _automation), do: {:error, :missing_endpoint_id}

  defp authorize_endpoint(endpoint, automation) do
    project = Repo.get(Projects.Project, automation.project_id)

    if project && project.account_id == endpoint.account_id do
      :ok
    else
      {:error, :cross_account}
    end
  end

  defp enqueue(endpoint, payload) do
    %{
      "webhook_endpoint_id" => endpoint.id,
      "event_id" => payload["id"],
      "event_type" => payload["type"],
      "payload" => payload
    }
    |> DeliveryWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp envelope(automation, endpoint, test_case) do
    %{
      "id" => Ecto.UUID.generate(),
      "type" => "test_case.updated",
      "created" => System.system_time(:second),
      "endpoint" => %{"id" => endpoint.id, "name" => endpoint.name},
      "automation" => %{"id" => automation.id, "name" => automation.name},
      "object" => test_case_snapshot(test_case)
    }
  end

  defp test_case_snapshot(test_case) do
    %{
      "id" => test_case.id,
      "name" => test_case.name,
      "module_name" => test_case.module_name,
      "suite_name" => test_case.suite_name,
      "project_id" => test_case.project_id,
      "is_flaky" => test_case.is_flaky,
      "state" => test_case.state,
      "last_status" => test_case.last_status,
      "last_ran_at" => format_datetime(Map.get(test_case, :last_ran_at))
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_datetime(other), do: to_string(other)
end
