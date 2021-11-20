# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "noreply@cloud.tuist.io"
  layout "mailer"
end
