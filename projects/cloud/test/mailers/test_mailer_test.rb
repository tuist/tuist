# frozen_string_literal: true

require "test_helper"

class TestMailerTest < ActionMailer::TestCase
  test "test" do
    mail = TestMailer.test
    assert_equal "Test", mail.subject
    assert_equal ["pedro@ppinera.es"], mail.to
    assert_equal ["noreply@cloud.tuist.io"], mail.from
    assert_match "Hi", mail.body.encoded
  end
end
