defmodule Atlas.Letters.Workers.ScheduleDeliveryChecks do
  @moduledoc false

  use Oban.Worker,
    queue: :mailing,
    max_attempts: 1,
    unique: [period: 300, fields: [:worker]],
    tags: ["letters", "pingen"]

  alias Atlas.Letters
  alias Atlas.Letters.Workers.SyncDelivery

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Letters.configured?() do
      Letters.list_delivery_check_candidate_ids()
      |> Enum.reduce_while(:ok, fn letter_id, :ok ->
        %{letter_id: letter_id}
        |> SyncDelivery.new()
        |> Oban.insert()
        |> case do
          {:ok, _job} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      :ok
    end
  end
end
