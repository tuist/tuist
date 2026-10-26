defmodule Tuist.IngestRepo.RetryPolicyTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.ClickHouseRetry
  alias Tuist.IngestRepo
  alias Tuist.Tests.Test

  test "durable publishers can opt out while ordinary ingestion retains its retries" do
    parent = self()

    stub(ClickHouseRetry, :with_retry, fn fun ->
      send(parent, :generic_retry_wrapper)
      fun.()
    end)

    assert {0, nil} = IngestRepo.insert_all(Test, [], retry: false)
    refute_receive :generic_retry_wrapper
    assert {0, nil} = IngestRepo.insert_all(Test, [])
    assert_receive :generic_retry_wrapper
  end
end
