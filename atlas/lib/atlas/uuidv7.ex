defmodule Atlas.UUIDv7 do
  use Ecto.Type

  def type, do: :uuid

  def cast(<<_::288>> = hex), do: Ecto.UUID.cast(hex)
  def cast(_), do: :error

  def dump(uuid), do: Ecto.UUID.dump(uuid)

  def load(<<_::128>> = raw), do: Ecto.UUID.load(raw)
  def load(_), do: :error

  def generate do
    Uniq.UUID.uuid7()
  end

  def autogenerate, do: generate()
end
