defmodule Atlas.Letters.Workers.SendLetter do
  @moduledoc false

  use Oban.Worker,
    queue: :mailing,
    max_attempts: 5,
    unique: [period: 60, fields: [:worker, :args]],
    tags: ["letters", "pingen"]

  alias Atlas.Letters

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"letter_id" => letter_id}}) do
    case Letters.deliver(letter_id) do
      {:ok, _letter} -> :ok
      :ok -> :ok
      {:error, :not_found} -> {:cancel, :letter_not_found}
      {:error, :postal_delivery_not_configured} -> {:cancel, :postal_delivery_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end
end
