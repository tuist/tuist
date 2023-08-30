if Rails.env.development? || Rails.env.testing?
  Que::Job.run_synchronously = true
end
