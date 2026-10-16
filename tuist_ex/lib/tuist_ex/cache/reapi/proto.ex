defmodule TuistEx.Cache.Reapi.Digest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:hash, 1, type: :string)
  field(:size_bytes, 2, type: :int64)
end

defmodule TuistEx.Cache.Reapi.OutputFile do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:path, 1, type: :string)
  field(:digest, 2, type: TuistEx.Cache.Reapi.Digest)
  field(:is_executable, 4, type: :bool)
  field(:contents, 5, type: :bytes)
end

defmodule TuistEx.Cache.Reapi.ActionResult do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:output_files, 2, repeated: true, type: TuistEx.Cache.Reapi.OutputFile)
  field(:exit_code, 4, type: :int32)
end

defmodule TuistEx.Cache.Reapi.GetActionResultRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:instance_name, 1, type: :string)
  field(:action_digest, 2, type: TuistEx.Cache.Reapi.Digest)
end

defmodule TuistEx.Cache.Reapi.UpdateActionResultRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:instance_name, 1, type: :string)
  field(:action_digest, 2, type: TuistEx.Cache.Reapi.Digest)
  field(:action_result, 3, type: TuistEx.Cache.Reapi.ActionResult)
end

defmodule TuistEx.Cache.Reapi.ToolDetails do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:tool_name, 1, type: :string)
  field(:tool_version, 2, type: :string)
end

defmodule TuistEx.Cache.Reapi.RequestMetadata do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:tool_details, 1, type: TuistEx.Cache.Reapi.ToolDetails)
  field(:action_id, 2, type: :string)
  field(:tool_invocation_id, 3, type: :string)
  field(:action_mnemonic, 5, type: :string)
  field(:target_id, 6, type: :string)
  field(:configuration_id, 7, type: :string)
end

defmodule TuistEx.Cache.Reapi.ActionCache.Service do
  @moduledoc false
  use GRPC.Service, name: "build.bazel.remote.execution.v2.ActionCache"

  rpc(
    :GetActionResult,
    TuistEx.Cache.Reapi.GetActionResultRequest,
    TuistEx.Cache.Reapi.ActionResult
  )

  rpc(
    :UpdateActionResult,
    TuistEx.Cache.Reapi.UpdateActionResultRequest,
    TuistEx.Cache.Reapi.ActionResult
  )
end

defmodule TuistEx.Cache.Reapi.ActionCache.Stub do
  @moduledoc false
  use GRPC.Stub, service: TuistEx.Cache.Reapi.ActionCache.Service
end

defmodule TuistEx.Cache.Reapi.ByteStream.Service do
  @moduledoc false
  use GRPC.Service, name: "google.bytestream.ByteStream"

  rpc(:Read, Google.Bytestream.ReadRequest, stream(Google.Bytestream.ReadResponse))
  rpc(:Write, stream(Google.Bytestream.WriteRequest), Google.Bytestream.WriteResponse)
end

defmodule TuistEx.Cache.Reapi.ByteStream.Stub do
  @moduledoc false
  use GRPC.Stub, service: TuistEx.Cache.Reapi.ByteStream.Service
end
