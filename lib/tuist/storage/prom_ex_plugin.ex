defmodule Tuist.Storage.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist storage events.
  """
  use PromEx.Plugin

  alias Tuist.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_storage_get_object_size,
        [
          distribution(
            [
              :tuist,
              :storage,
              :get_object_size,
              :size,
              :bytes
            ],
            event_name: Telemetry.event_name_storage_get_object_as_string_size(),
            measurement: :size,
            unit: :bytes,
            description: "The size in bytes of an object.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          distribution(
            [
              :tuist,
              :storage,
              :get_object_size,
              :duration,
              :milliseconds
            ],
            event_name: Telemetry.event_name_storage_get_object_as_string_size(),
            measurement: :duration,
            unit: :millisecond,
            description: "The time in milliseconds that takes to get the size of an object.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          counter(
            [
              :tuist,
              :storage,
              :get_object_size,
              :count
            ],
            event_name: Telemetry.event_name_storage_get_object_as_string_size(),
            description: "The number of times the size of an object has been retrieved."
          )
        ]
      ),
      Event.build(
        :tuist_storage_delete_all_objects,
        [
          distribution(
            [
              :tuist,
              :storage,
              :delete_all_objects,
              :duration,
              :milliseconds
            ],
            event_name: Telemetry.event_name_storage_delete_all_objects(),
            measurement: :duration,
            unit: :millisecond,
            description: "The time in milliseconds that takes to delete all objects.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          counter(
            [
              :tuist,
              :storage,
              :delete_all_objects,
              :count
            ],
            event_name: Telemetry.event_name_storage_delete_all_objects(),
            description: "The count of times that all objects have been deleted."
          )
        ]
      ),
      Event.build(
        :tuist_storage_multipart_start_upload,
        [
          distribution(
            [
              :tuist,
              :storage,
              :multipart,
              :start_upload,
              :duration,
              :milliseconds
            ],
            event_name: Telemetry.event_name_storage_multipart_start_upload(),
            measurement: :duration,
            unit: :millisecond,
            description: "The time in milliseconds that takes to start a multi-part upload.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          counter(
            [
              :tuist,
              :storage,
              :multipart,
              :start_upload,
              :count
            ],
            event_name: Telemetry.event_name_storage_multipart_start_upload(),
            description: "The count of multi-part uploads that have been started."
          )
        ]
      ),
      Event.build(
        :tuist_storage_get_object_as_string,
        [
          distribution(
            [
              :tuist,
              :storage,
              :get_object_as_string,
              :duration,
              :milliseconds
            ],
            event_name: Telemetry.event_name_storage_get_object_as_string(),
            measurement: :duration,
            unit: :millisecond,
            description: "The time in milliseconds that takes to download an object as string from the storage.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          counter(
            [
              :tuist,
              :storage,
              :get_object_as_string,
              :count
            ],
            event_name: Telemetry.event_name_storage_get_object_as_string(),
            description: "The count of objects that have been downloaded as string from the storage."
          )
        ]
      ),
      Event.build(
        :tuist_storage_check_object_existence,
        [
          distribution(
            [
              :tuist,
              :storage,
              :check_object_existence,
              :duration,
              :milliseconds
            ],
            event_name: Telemetry.event_name_storage_check_object_existence(),
            measurement: :duration,
            unit: :millisecond,
            description: "The time in milliseconds that takes to check the existence of an object.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          counter(
            [
              :tuist,
              :storage,
              :check_object_existence,
              :count
            ],
            event_name: Telemetry.event_name_storage_check_object_existence(),
            description: "The count of checks that have been performed to verify the existence of an object."
          )
        ]
      ),
      Event.build(
        :tuist_storage_generate_download_presigned_url,
        [
          distribution(
            [
              :tuist,
              :storage,
              :generate_download_presigned_url,
              :duration,
              :milliseconds
            ],
            event_name: Telemetry.event_name_storage_generate_download_presigned_url(),
            measurement: :duration,
            unit: :millisecond,
            description: "The time in milliseconds that takes to generate a pre-signed URL to download an object.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          counter(
            [
              :tuist,
              :storage,
              :generate_download_presigned_url,
              :count
            ],
            event_name: Telemetry.event_name_storage_generate_download_presigned_url(),
            description: "The count of pre-signed URLs that have been generated to download an object."
          )
        ]
      ),
      Event.build(
        :tuist_storage_generate_upload_presigned_url,
        [
          counter(
            [
              :tuist,
              :storage,
              :generate_upload_presigned_url,
              :count
            ],
            event_name: Telemetry.event_name_storage_generate_upload_presigned_url(),
            description: "The count of pre-signed URLs that have been generated to upload an object."
          )
        ]
      ),
      Event.build(
        :tuist_storage_multipart_generate_upload_part_presigned_url,
        [
          counter(
            [
              :tuist,
              :storage,
              :multipart,
              :generate_upload_part_presigned_url,
              :count
            ],
            event_name: Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url(),
            description: "The count of pre-signed URLs that have been generated to upload a part."
          )
        ]
      ),
      Event.build(
        :tuist_storage_multipart_complete_upload,
        [
          counter(
            [
              :tuist,
              :storage,
              :multipart,
              :complete_upload,
              :duration,
              :count
            ],
            event_name: Telemetry.event_name_storage_multipart_complete_upload(),
            description: "The numer of multi-part uploads that have been completed"
          ),
          distribution(
            [
              :tuist,
              :storage,
              :multipart,
              :complete_upload,
              :duration,
              :milliseconds
            ],
            event_name: Telemetry.event_name_storage_multipart_complete_upload(),
            measurement: :duration,
            unit: :millisecond,
            description: "The time in milliseconds that takes the storage to complete a multi-part upload.",
            reporter_options: [
              buckets: exponential!(100, 2, 15)
            ]
          ),
          sum(
            [
              :tuist,
              :storage,
              :multipart,
              :complete_upload,
              :duration,
              :parts_count
            ],
            event_name: Telemetry.event_name_storage_multipart_complete_upload(),
            measurement: :parts_count,
            description: "The number of parts a multi-part upload has been completed with."
          )
        ]
      ),
      Event.build(
        :tuist_storage_stream_object,
        [
          counter(
            [
              :tuist,
              :storage,
              :stream_object,
              :count
            ],
            event_name: Telemetry.event_name_storage_stream_object(),
            description: "The count of times that objects have been streamed."
          )
        ]
      )
    ]
  end
end
