# frozen_string_literal: true

require "test_helper"

class UpdateCacheEventCountsJobTest < ActiveSupport::TestCase
  test "cache event counts are updated" do
    # Given
    organization = Organization.create!
    account_one = Account.create!(owner: organization, name: "tuist", customer_id: "customer_id")

    ENV["TZ"] = "UTC"
    Time.stubs(:now).returns(Time.new(2022, 8, 31, 10, 0, 20))
    created_at = Time.new(2022, 8, 31, 10, 0, 10)

    project_one = Project.create!(account: account_one, name: "tuist")
    CacheEvent.create!(project: project_one, size: 100, event_type: :upload, name: "generate", created_at: Time.new(2022, 9, 30))
    CacheEvent.create!(project: project_one, size: 100, event_type: :upload, name: "generate", created_at: created_at)
    CacheEvent.create!(project: project_one, size: 100, event_type: :download, name: "generate", created_at: created_at)
    CacheEvent.create!(project: project_one, size: 100, event_type: :upload, name: "generate", created_at: created_at)

    project_two = Project.create!(account: organization.account, name: "tuist-two")
    CacheEvent.create!(project: project_two, size: 100, event_type: :upload, name: "generate", created_at: created_at)

    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    user.account.update(customer_id: "customer_id_two")

    project_three = Project.create!(account: user.account, name: "tuist-three")
    CacheEvent.create!(project: project_three, size: 100, event_type: :upload, name: "generate", created_at: created_at)

    # When
    UpdateCacheEventCountsJob.enqueue

    # Then
    assert_equal 3, Account.first.cache_upload_event_count
    assert_equal 1, Account.first.cache_download_event_count
  end
end
