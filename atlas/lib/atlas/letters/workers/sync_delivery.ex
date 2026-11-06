defmodule Atlas.Letters.Workers.SyncDelivery do
  @moduledoc false

  use Oban.Worker,
    queue: :mailing,
    max_attempts: 3,
    unique: [period: 300, fields: [:worker, :args]],
    tags: ["letters", "pingen"]

  alias Atlas.Letters

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"letter_id" => letter_id}}) do
    case Letters.sync_delivery(letter_id) do
      {:ok, _letter} -> :ok
      {:error, :not_found} -> {:cancel, :letter_not_found}
      {:error, :letter_not_submitted} -> {:cancel, :letter_not_submitted}
      {:error, :postal_delivery_not_configured} -> {:cancel, :postal_delivery_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end
end
