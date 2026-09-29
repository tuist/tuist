defmodule Tuist.OpenGraphImagesTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.OpenGraphImages
  alias Tuist.Storage

  setup :set_mimic_global

  describe "key/1" do
    test "is deterministic and changes with the rendering attributes" do
      assert OpenGraphImages.key(["page", "English", "Title"]) ==
               OpenGraphImages.key(["page", "English", "Title"])

      refute OpenGraphImages.key(["page", "English", "Title"]) ==
               OpenGraphImages.key(["page", "English", "Different title"])
    end
  end

  describe "spec/3" do
    test "keeps the signed template variables with the render function" do
      params = %{"template" => "marketing", "title" => "About Tuist"}
      render = fn -> {:ok, "image"} end

      spec = OpenGraphImages.spec(["marketing", "About Tuist"], params, render)

      assert spec.params == params
      assert spec.render == render
      assert spec.key == OpenGraphImages.key(["marketing", "About Tuist"])
    end
  end

  test "serializes same-image generation and permits unrelated images" do
    {:ok, objects} = Agent.start_link(fn -> MapSet.new() end)

    stub(Storage, :object_exists?, fn key, :open_graph_images ->
      Agent.get(objects, &MapSet.member?(&1, key))
    end)

    stub(Storage, :put_object, fn key, _image, :open_graph_images ->
      Agent.update(objects, &MapSet.put(&1, key))
    end)

    parent = self()

    resolve = fn ->
      {:ok,
       %{
         key: "same",
         render: fn ->
           send(parent, {:rendering, self()})

           receive do
             :finish -> {:ok, "image"}
           end
         end
       }}
    end

    first = Task.async(fn -> OpenGraphImages.ensure_available("same", resolve) end)
    assert_receive {:rendering, renderer}
    second = Task.async(fn -> OpenGraphImages.ensure_available("same", resolve) end)

    different =
      Task.async(fn ->
        OpenGraphImages.ensure_available("different", fn ->
          {:ok, %{key: "different", render: fn -> {:ok, "other image"} end}}
        end)
      end)

    assert Task.await(different, 1000) == :ok
    refute_receive {:rendering, _}, 1000
    assert Task.yield(second, 0) == nil
    send(renderer, :finish)
    assert Task.await(first) == :ok
    assert Task.await(second) == :ok
    refute_receive {:rendering, _}
  end
end
