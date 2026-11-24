defmodule Tuist.Repo.Migrations.AddCardToThreadMessages do
  use Ecto.Migration

  # A `card` message's NSH bundle and size class (`Tuist.Threads.Cards`); its
  # body is the card's text.
  def change do
    alter table(:thread_messages) do
      add :card_size, :text
      add :card_source, :text
    end
  end
end
