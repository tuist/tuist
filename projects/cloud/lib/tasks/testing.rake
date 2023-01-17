# frozen_string_literal: true

namespace :testing do
  task get_token: :environment do
    puts Account.find_by(name: "aletha").owner.token
  end
end
