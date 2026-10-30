defmodule TuistEx.Analytics.ShardUploadTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.ShardUpload

  test "uploads four parts concurrently, bounds concurrency and returns numbered parts in order" do
    parent = self()

    task =
      Task.async(fn ->
        ShardUpload.upload(1..6, fn chunk, number ->
          send(parent, {:part, self(), number, chunk})
          receive do: (:release -> {:ok, "etag-#{number}"})
        end)
      end)

    workers =
      for _ <- 1..4 do
        assert_receive {:part, pid, number, chunk}
        assert number == chunk
        {number, pid}
      end

    refute_receive {:part, _, _, _}, 50
    workers |> Enum.sort(:desc) |> Enum.each(fn {_, pid} -> send(pid, :release) end)

    for _ <- 1..2 do
      assert_receive {:part, pid, _, _}
      send(pid, :release)
    end

    assert {:ok, parts} = Task.await(task)
    assert parts == Enum.map(1..6, &%{part_number: &1, etag: "etag-#{&1}"})
  end

  test "retries transient failures at most three times, preserving chunk and part number" do
    parent = self()

    assert {:ok, [%{part_number: 1, etag: "ok"}]} =
             ShardUpload.upload(
               ["bytes"],
               fn "bytes", 1 ->
                 attempt = Process.get(:attempt, 0) + 1
                 Process.put(:attempt, attempt)
                 send(parent, {:attempt, attempt})
                 if attempt < 3, do: {:error, {:http, 503}}, else: {:ok, "ok"}
               end,
               sleep: fn _ -> :ok end
             )

    for i <- 1..3, do: assert_received({:attempt, ^i})

    assert {:error, :timeout} =
             ShardUpload.upload(["bytes"], fn _, _ -> {:error, :timeout} end,
               sleep: fn _ -> :ok end
             )
  end

  test "does not retry permanent rejection" do
    parent = self()

    assert {:error, {:http, 403}} =
             ShardUpload.upload(
               ["bytes"],
               fn _, _ ->
                 send(parent, :attempt)
                 {:error, {:http, 403}}
               end,
               sleep: fn _ -> flunk("must not retry") end
             )

    assert_received :attempt
    refute_received :attempt
  end
end
