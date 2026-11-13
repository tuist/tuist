defmodule Pulse.Storage.S3.KeyedPublication do
  @moduledoc false

  alias Pulse.ObjectStore

  # A conditional create may commit even when its response is lost. Verify on
  # every failed create, not only 412. Never replace bytes under an existing
  # deterministic name, and never infer semantic equivalence from its hash.
  def put(config, key, payload, opts \\ []) do
    create(config, key, payload, 2, Keyword.get(opts, :deadline_ms))
  end

  defp create(config, key, payload, attempts, deadline) do
    if remaining(deadline) == 0 do
      {:error, :timeout}
    else
      recover(ObjectStore.put_if_none_match(config, key, payload), config, key, payload, attempts, deadline)
    end
  end

  defp recover(result, config, key, payload, attempts, deadline) do
    case result do
      {:ok, _etag} ->
        :ok

      {:error, reason} = error ->
        case ObjectStore.verify(config, key, payload, remaining(deadline)) do
          :ok ->
            :ok

          {:error, :keyed_content_mismatch} = mismatch ->
            Pulse.SelfMetrics.keyed_publication_conflict()
            mismatch

          {:error, :not_found} when reason == :already_exists and attempts > 1 ->
            # Cleanup or an intervening delete can race 412 -> GET. At most
            # two create/verify rounds; manifest retirement/floors still fence
            # registration even when this recreates an unreferenced object.
            create(config, key, payload, attempts - 1, deadline)

          {:error, _} when reason == :already_exists ->
            {:error, :keyed_recovery_unavailable}

          {:error, _} ->
            error
        end
    end
  end

  defp remaining(nil), do: 15_000

  defp remaining(deadline) when is_integer(deadline),
    do: max(0, min(15_000, deadline - System.monotonic_time(:millisecond)))

  defp remaining(_), do: 0
end
