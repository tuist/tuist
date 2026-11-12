defmodule Pulse.Storage.S3.Manifest.Retirement do
  @moduledoc "Durable deletion state for a superseded segment, retained for ingest idempotency."

  defstruct [:delete_after, revision: 0, deleted?: false]

  @type t :: %__MODULE__{delete_after: non_neg_integer(), revision: non_neg_integer(), deleted?: boolean()}

  def new(deadline), do: %__MODULE__{delete_after: deadline}

  # A retry can re-upload a retired object. Incrementing the revision ensures
  # an overlapping cleanup cannot mark that new upload as already deleted.
  def retried(retirement), do: %{retirement | revision: retirement.revision + 1, deleted?: false}

  def to_wire(retirement) do
    %{"d" => retirement.delete_after, "g" => retirement.revision, "x" => retirement.deleted?}
  end

  def from_wire(%{"d" => deadline, "g" => revision, "x" => deleted})
      when is_integer(deadline) and deadline >= 0 and is_integer(revision) and revision >= 0 and is_boolean(deleted) do
    {:ok, %__MODULE__{delete_after: deadline, revision: revision, deleted?: deleted}}
  end

  def from_wire(_), do: {:error, :invalid_manifest}
end
