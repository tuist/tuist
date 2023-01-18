# frozen_string_literal: true

namespace :testing do
  task get_token: :environment do
    ARGV.each { |a| task a.to_sym do ; end }
    puts Account.find_by(name: ARGV[0]).owner.token
  end

  task get_account_name: :environment do
    puts User.first.account.name
  end
end
