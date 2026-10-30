defmodule Atlas.Automations.Trigger do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Automations.Revision
  alias Atlas.Users.User
  alias Oban.Cron.Expression

  schema "automation_triggers" do
    field :name, :string
    field :kind, :string
    field :enabled, :boolean, default: true
    field :cron, :string
    field :next_run_at, :utc_datetime
    field :token_hash, :binary, redact: true
    field :input, :map, default: %{}
    belongs_to :revision, Revision
    belongs_to :execution_user, User
    timestamps(type: :utc_datetime)
  end

  def changeset(trigger, attrs) do
    trigger
    |> cast(attrs, [:name, :kind, :cron, :input])
    |> validate_required([:name, :kind, :input])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:kind, ["schedule", "webhook"])
    |> validate_cron()
  end

  defp validate_cron(changeset) do
    if get_field(changeset, :kind) == "schedule" do
      case Expression.parse(get_field(changeset, :cron) || "") do
        {:ok, %{reboot?: false} = expression} ->
          possible? =
            Enum.any?(expression.months, fn month ->
              Enum.any?(expression.days, &(&1 <= Calendar.ISO.days_in_month(2000, month)))
            end)

          if possible?, do: changeset, else: add_error(changeset, :cron, "must have a possible calendar date")

        _ ->
          add_error(changeset, :cron, "must be a recurring UTC cron expression")
      end
    else
      changeset
    end
  end
end
