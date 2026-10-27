defmodule Atlas.Finance.Workers.BackfillQontoInvoices do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Finance

  @impl true
  def perform(%Oban.Job{args: args}) do
    opts =
      [
        source_key: present(args["source_key"]),
        batch_size: positive_integer(args["batch_size"]),
        max_transactions: positive_integer(args["max_transactions"])
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Finance.backfill_qonto_invoices(opts) do
      {:ok, _summary} -> :ok
      {:error, :qonto_source_not_configured} -> {:cancel, :qonto_source_not_configured}
      {:error, :source_not_configured} -> {:cancel, :source_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil
end
