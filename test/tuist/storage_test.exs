defmodule Tuist.StorageTest do
  use ExUnit.Case, async: false
  use Mimic
  alias Tuist.Native
  alias Tuist.Storage

  describe "multipart_generate_url/4" do
    test "executes a telemetry event" do
      # Given
      url = "https://tuist.io/upload-url"

      event_name =
        Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      Native
      |> stub(:s3_multipart_generate_url, fn _ ->
        {:ok, url}
      end)

      # When
      assert Storage.multipart_generate_url("object-key", "upload-id", 1) == url

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration},
                       %{object_key: "object-key", upload_id: "upload-id", part_number: 1}}

      assert is_number(duration)
    end
  end

  describe "multipart_complete_upload/3" do
    test "executes a telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_multipart_complete_upload()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      Native
      |> stub(:s3_multipart_complete_upload, fn _ ->
        :ok
      end)

      # When
      assert Storage.multipart_complete_upload("object-key", "upload-id", []) == :ok

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration, parts_count: 0},
                       %{object_key: "object-key", upload_id: "upload-id"}}

      assert is_number(duration)
    end
  end

  describe "generate_download_url/2" do
    test "executes a telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_generate_download_presigned_url()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      url = "https://tuist.io/download-url"

      Native
      |> stub(:s3_download_presigned_url, fn _ ->
        {:ok, url}
      end)

      # When
      assert Storage.generate_download_url("object-key") == url

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration},
                       %{object_key: "object-key"}}

      assert is_number(duration)
    end
  end

  describe "object_exists?/1" do
    test "executes a telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_check_object_existence()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      Native
      |> stub(:s3_exists, fn _ ->
        {:ok, true}
      end)

      # When
      assert Storage.object_exists?("object-key") == true

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration},
                       %{object_key: "object-key"}}

      assert is_number(duration)
    end
  end

  describe "get_object_as_string/1" do
    test "executes a telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_get_object_as_string()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      object = "object"

      Native
      |> stub(:s3_get_object_as_string, fn _ ->
        {:ok, object}
      end)

      # When
      assert Storage.get_object_as_string("object-key") == {:ok, object}

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration},
                       %{object_key: "object-key"}}

      assert is_number(duration)
    end
  end

  describe "multipart_start/1" do
    test "executes a telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_multipart_start_upload()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      upload_id = "upload-id"

      Native
      |> stub(:s3_multipart_start, fn _ ->
        {:ok, upload_id}
      end)

      # When
      assert Storage.multipart_start("object-key") == {:ok, upload_id}

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration},
                       %{object_key: "object-key"}}

      assert is_number(duration)
    end
  end

  describe "delete_all_objects/1" do
    test "executes a telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_delete_all_objects()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      Native
      |> stub(:s3_delete_all_objects, fn _ ->
        :ok
      end)

      # When
      assert Storage.delete_all_objects("object-key") == :ok

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{}}

      assert is_number(duration)
    end
  end

  describe "get_object_size/1" do
    test "executes a telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_get_object_as_string_size()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      size = 25

      Native
      |> stub(:s3_size, fn _ ->
        {:ok, size}
      end)

      # When
      assert Storage.get_object_size("object-key") == {:ok, size}

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration, size: size},
                       %{object_key: "object-key"}}

      assert is_number(size)
      assert is_number(duration)
    end
  end
end
