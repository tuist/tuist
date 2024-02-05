# frozen_string_literal: true

if Rails.env.test?
  Que::Job.run_synchronously = true
end
