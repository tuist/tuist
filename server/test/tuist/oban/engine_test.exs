defmodule Tuist.Oban.EngineTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Oban.Engines.Basic
  alias Tuist.Oban.Engine

  test "is configured as the Oban engine" do
    assert Oban.config().engine == Engine
  end

  test "retries a rolled-back Oban insertion" do
    changeset = Ecto.Changeset.change(%Oban.Job{})
    job = %Oban.Job{}
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Mimic.expect(Basic, :insert_job, 2, fn _conf, ^changeset, [] ->
      attempt = Agent.get_and_update(counter, &{&1, &1 + 1})

      case attempt do
        0 -> {:error, :rollback}
        1 -> {:ok, job}
      end
    end)

    assert {:ok, ^job} = Oban.insert(changeset)
  end

  test "returns other insertion errors without retrying" do
    changeset = Ecto.Changeset.change(%Oban.Job{})

    Mimic.expect(Basic, :insert_job, 1, fn _conf, ^changeset, [] -> {:error, :invalid} end)

    assert {:error, :invalid} = Engine.insert_job(%Oban.Config{}, changeset, [])
  end

  test "returns a rollback after exhausting retries" do
    changeset = Ecto.Changeset.change(%Oban.Job{})

    Mimic.expect(Basic, :insert_job, 4, fn _conf, ^changeset, [] -> {:error, :rollback} end)

    assert {:error, :rollback} = Engine.insert_job(%Oban.Config{}, changeset, [])
  end
end
