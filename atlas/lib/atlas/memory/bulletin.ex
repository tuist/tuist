defmodule Atlas.Memory.Bulletin do
  @moduledoc """
  A synthesized briefing of the current memory state, prepended to the
  Atlas Slack agent's system prompt. One row per scope.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Slack.Channel, as: SlackChannel

  @scopes [:global, :channel]

  schema "memory_bulletins" do
    field :scope, Ecto.Enum, values: @scopes, default: :global
    field :body, :string
    field :generated_at, :utc_datetime

    belongs_to :slack_channel, SlackChannel

    timestamps()
  end

  def changeset(bulletin, attrs) do
    bulletin
    |> cast(attrs, [:scope, :body])
    |> validate_required([:scope, :body])
    |> put_generated_at()
  end

  # generated_at is set programmatically every time the bulletin is written,
  # never from caller-supplied attrs, so synthesis cannot forge a future
  # timestamp through the changeset.
  defp put_generated_at(changeset) do
    Ecto.Changeset.put_change(
      changeset,
      :generated_at,
      DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end
end
