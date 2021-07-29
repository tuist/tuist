# typed: ignore
# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "noreply@tuist.io"
  layout "mailer"
end
