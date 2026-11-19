defmodule Atlas.Repo.Migrations.AddCodingEnvironmentTools do
  use Ecto.Migration

  def up do
    drop constraint(:environment_commands, :supported_tool)

    create constraint(:environment_commands, :supported_tool,
             check:
               "tool IN ('environment_list_directory', 'environment_read_file', 'environment_terminal', 'read', 'bash', 'edit', 'write')"
           )
  end

  def down do
    # Never delete coding evidence on rollback. NOT VALID permits historical
    # rows while rejecting new coding commands after the server is rolled back.
    drop constraint(:environment_commands, :supported_tool)

    create constraint(:environment_commands, :supported_tool,
             check:
               "tool IN ('environment_list_directory', 'environment_read_file', 'environment_terminal')",
             validate: false
           )
  end
end
