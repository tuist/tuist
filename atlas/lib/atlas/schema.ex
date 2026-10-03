defmodule Atlas.Schema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, Atlas.UUIDv7, autogenerate: true}
      @foreign_key_type Atlas.UUIDv7
    end
  end
end
