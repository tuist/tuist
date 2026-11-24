defmodule LuftServer.Repo.Migrations.CreateNotificationProjections do
  use Ecto.Migration

  def change, do: LuftServer.Notifications.Migration.change()
end
