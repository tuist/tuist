defmodule Tuist.Automations.Actions.SendWebhookAction do
  @moduledoc """
  Automation action that POSTs a Stripe-style event envelope to a user-
  configured HTTPS endpoint.

  Execution is asynchronous: the action enqueues a
  `Tuist.Webhooks.Workers.DeliveryWorker` Oban job and returns `:ok`. The
  worker performs the actual HTTP call and handles retries on the RFC
  schedule, so a slow or temporarily unreachable endpoint cannot block
  subsequent actions on the same automation.
  """
  alias Tuist.Tests
  alias Tuist.Webhooks.Workers.DeliveryWorker

  require Logger

  def execute(automation, %{type: :test_case, id: test_case_id}, action) do
    case Tests.get_test_case_by_id(test_case_id) do
      {:ok, test_case} ->
        payload = envelope(automation, test_case)
        enqueue(action, payload, automation)

      {:error, :not_found} ->
        Logger.warning("Automation #{automation.id} send_webhook skipped: test case #{test_case_id} not found")

        :ok

      other ->
        Logger.warning(
          "Automation #{automation.id} send_webhook skipped for test case #{test_case_id}: #{inspect(other)}"
        )

        :ok
    end
  end

  defp enqueue(%{"url" => url, "signing_secret_encrypted" => encrypted}, payload, _automation)
       when is_binary(url) and is_binary(encrypted) and encrypted != "" do
    %{
      "url" => url,
      "signing_secret_encrypted" => encrypted,
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

  defp enqueue(_action, _payload, automation) do
    Logger.warning("Automation #{automation.id} send_webhook skipped: missing url or signing_secret_encrypted")

    :ok
  end

  defp envelope(automation, test_case) do
    %{
      "id" => Ecto.UUID.generate(),
      "type" => "test_case.updated",
      "created" => System.system_time(:second),
      "project" => to_string(test_case.project_id),
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
