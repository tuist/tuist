defmodule Atlas.Engineering.Errors.SummarySettings do
  @moduledoc """
  Runtime-managed error summary settings.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "error_summary_settings" do
    field :enabled, :boolean, default: false
    field :schedule, :string, default: "0 9 * * *"
    field :slack_channel_id, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :schedule, :slack_channel_id])
    |> update_change(:schedule, &normalize_string/1)
    |> update_change(:slack_channel_id, &normalize_string/1)
    |> validate_required([:id, :enabled, :schedule])
    |> validate_length(:schedule, max: 120)
    |> validate_length(:slack_channel_id, max: 80)
    |> validate_schedule()
    |> validate_channel_when_enabled()
    |> unique_constraint(:id)
  end

  defp validate_schedule(changeset) do
    validate_change(changeset, :schedule, fn :schedule, schedule ->
      with 5 <- schedule |> String.split() |> length(),
           {:ok, _expression} <- Oban.Plugins.Cron.parse(schedule) do
        []
      else
        _other -> [schedule: "must be a valid five-field Cron schedule"]
      end
    end)
  end

  defp validate_channel_when_enabled(changeset) do
    if get_field(changeset, :enabled) do
      validate_required(changeset, [:slack_channel_id])
    else
      changeset
    end
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value), do: value
end
