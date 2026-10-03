defmodule Atlas.LLMs.Errors do
  @moduledoc false

  @hard_statuses [401, 402, 403, 412]

  @credit_markers [
    "credit_limit",
    "credit limit",
    "insufficient credits",
    "zero balance",
    "payment required"
  ]

  @suspension_markers [
    "account is suspended",
    "account suspended",
    "billing issue",
    "failure to pay",
    "spending limit"
  ]

  @credential_markers [
    "invalid api key",
    "invalid_api_key",
    "missing or invalid inference token",
    "unauthorized"
  ]

  def hard_failure?(reason), do: not is_nil(hard_failure_reason(reason))

  def hard_failure_reason(reason) do
    text = reason_text(reason)

    cond do
      contains_any?(text, @credit_markers) ->
        :llm_credit_limit

      contains_any?(text, @suspension_markers) ->
        :llm_provider_account_suspended

      contains_any?(text, @credential_markers) ->
        :llm_invalid_credentials

      status_code(reason) in @hard_statuses ->
        :llm_provider_rejected_request

      true ->
        nil
    end
  end

  def oban_error(reason) do
    case hard_failure_reason(reason) do
      nil -> {:error, reason}
      hard_reason -> {:cancel, hard_reason}
    end
  end

  defp reason_text(reason) do
    reason
    |> inspect(limit: 100, printable_limit: 2_000)
    |> String.downcase()
  end

  defp contains_any?(text, markers), do: Enum.any?(markers, &String.contains?(text, &1))

  defp status_code({:embedding_request_failed, status, _body}) when is_integer(status), do: status
  defp status_code({:error, reason}), do: status_code(reason)

  defp status_code(status) when is_integer(status) and status in 100..599, do: status

  defp status_code(%{status: status}) when is_integer(status), do: status
  defp status_code(%{"status" => status}) when is_integer(status), do: status
  defp status_code(%{body: body}), do: status_code(body)
  defp status_code(%{"body" => body}), do: status_code(body)
  defp status_code(%{reason: reason}), do: status_code(reason)
  defp status_code(%{"reason" => reason}), do: status_code(reason)
  defp status_code(%{"error" => error}), do: status_code(error)

  defp status_code(values) when is_list(values), do: Enum.find_value(values, &status_code/1)

  defp status_code(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.find_value(&status_code/1)
  end

  defp status_code(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.find_value(&status_code/1)
  end

  defp status_code(_reason), do: nil
end
