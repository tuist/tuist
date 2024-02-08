# frozen_string_literal: true

require "test_helper"

class CacheClearServiceTest < ActiveSupport::TestCase
  class ContentsMock
    class CacheObject
      attr_reader :key

      def initialize(key:)
        @key = key
      end
    end

    def contents
      [CacheObject.new(key: "key")]
    end

    def next_marker
      nil
    end
  end
  setup do
    @user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    @s3_bucket = @user.account.s3_buckets.create!(
      name: "project-bucket",
      access_key_id: "access key id",
      secret_access_key: "encoded secret",
      iv: "random iv",
      region: "region",
    )
    DecipherService.stubs(:call).returns("decoded secret")
  end

  test "cache is cleared with project slug" do
    # Given
    client = mock("s3-client").responds_like_instance_of(Aws::S3::Client)
    S3ClientService.expects(:call).returns([client, "bucket"])
    client.expects(:delete_objects)
    client.expects(:list_objects).returns(ContentsMock.new)
    project = Project.create!(
      name: "tuist-project",
      account_id: @user.account.id,
      token: Devise.friendly_token.first(16),
    )
    ProjectFetchService.any_instance.stubs(:fetch_by_slug).returns(project)

    # When/then
    CacheClearService.call(
      project_slug: "project/slug",
      subject: @user,
    )
  end
end
