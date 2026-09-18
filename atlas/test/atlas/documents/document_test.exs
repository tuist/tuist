defmodule Atlas.Documents.DocumentTest do
  use Atlas.DataCase, async: true

  alias Atlas.Documents.Document
  alias Atlas.Documents.Tag

  describe "schema" do
    test "sets defaults" do
      document = %Document{}

      assert document.source == "upload"
      assert document.status == "uploaded"
      assert document.attributes == %{}
    end
  end

  describe "changeset/2" do
    test "requires the core upload fields" do
      changeset = Document.changeset(%Document{}, %{})

      refute changeset.valid?

      assert errors_on(changeset) == %{
               title: ["can't be blank"],
               original_filename: ["can't be blank"],
               content_type: ["can't be blank"],
               byte_size: ["can't be blank"],
               checksum_sha256: ["can't be blank"],
               storage_bucket: ["can't be blank"],
               storage_key: ["can't be blank"]
             }
    end

    test "is valid with the required fields" do
      assert Document.changeset(%Document{}, valid_attrs()).valid?
    end

    test "accepts every supported source" do
      for source <- Document.sources() do
        changeset = Document.changeset(%Document{}, Map.put(valid_attrs(), "source", source))
        assert changeset.valid?, "expected source #{source} to be valid"
      end
    end

    test "rejects unknown sources" do
      changeset = Document.changeset(%Document{}, Map.put(valid_attrs(), "source", "scanner"))

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).source
    end

    test "accepts every supported status" do
      for status <- Document.statuses() do
        changeset = Document.changeset(%Document{}, Map.put(valid_attrs(), "status", status))
        assert changeset.valid?, "expected status #{status} to be valid"
      end
    end

    test "rejects unknown statuses" do
      changeset = Document.changeset(%Document{}, Map.put(valid_attrs(), "status", "archived"))

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "enforces a unique storage bucket and key" do
      attrs = valid_attrs()

      assert {:ok, _} = %Document{} |> Document.changeset(attrs) |> Repo.insert()

      assert {:error, changeset} = %Document{} |> Document.changeset(attrs) |> Repo.insert()
      assert "has already been taken" in errors_on(changeset).storage_bucket
    end

    test "enforces a unique archive serial number" do
      first = Map.put(valid_attrs(), "archive_serial_number", 1)

      second =
        valid_attrs()
        |> Map.merge(%{"archive_serial_number" => 1, "storage_key" => "#{unique("documents/cd/")}.pdf"})

      assert {:ok, _} = %Document{} |> Document.changeset(first) |> Repo.insert()

      assert {:error, changeset} = %Document{} |> Document.changeset(second) |> Repo.insert()
      assert "has already been taken" in errors_on(changeset).archive_serial_number
    end

    test "reports a missing correspondent association" do
      # correspondent_id is set explicitly (not cast) to mirror how the context
      # assigns programmatic foreign keys.
      changeset =
        %Document{}
        |> Document.changeset(valid_attrs())
        |> Ecto.Changeset.put_change(:correspondent_id, Atlas.UUIDv7.generate())

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).correspondent
    end
  end

  describe "tags_changeset/2" do
    test "replaces the tag associations" do
      tag = insert_tag!("finance")

      changeset = Document.tags_changeset(%Document{}, [tag])

      assert [tag_change] = get_change(changeset, :tags)
      assert tag_change.data.id == tag.id
    end
  end

  defp valid_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        "title" => "Service Agreement",
        "original_filename" => "service-agreement.pdf",
        "content_type" => "application/pdf",
        "byte_size" => 1024,
        "checksum_sha256" => unique("checksum"),
        "storage_bucket" => "test-documents",
        "storage_key" => "#{unique("documents/ab/")}.pdf",
        "source" => "upload",
        "status" => "uploaded"
      },
      attrs
    )
  end

  defp insert_tag!(name) do
    %Tag{}
    |> Tag.changeset(%{name: name, color: "information"})
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
