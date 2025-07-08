defmodule Tuist.Apple do
  @moduledoc false
  @devices "priv/apple.json"
           |> File.read!()
           |> Jason.decode!()
  def devices do
    @devices
  end
end
