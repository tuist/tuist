defmodule Atlas.Letters.Workers.PrepareDelivery do
  @moduledoc false

  use Oban.Worker,
    queue: :mailing,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]],
    tags: ["letters", "delivery_preparation"]

  alias Atlas.Audit
  alias Atlas.Letters

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"letter_id" => letter_id}}) do
    Audit.with_context(%{interface: "worker"}, fn ->
      case Letters.prepare_delivery_details(letter_id) do
        {:ok, _letter} -> :ok
        {:error, :not_found} -> {:cancel, :letter_not_found}
        {:error, :letter_not_waiting_for_delivery_details} -> :ok
        {:error, {:delivery_details_missing, _fields}} -> {:cancel, :delivery_details_missing}
        {:error, reason} -> {:error, reason}
      end
    end)
  end
end
