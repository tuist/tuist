defmodule Symptoms.Repo.Migrations.TrackUnknownStreams do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:entities) do
      add :unknown_streams, {:array, :string}, null: false, default: []
    end
  end
end
