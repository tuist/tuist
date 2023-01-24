# frozen_string_literal: true

# rubocop:disable Output

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

organization_ids = []

4.times do |index|
  organization = Organization.create!
  organization_ids.push(organization.id)
  account = Account.create!(
    name: Faker::Superhero.name,
    owner: organization,
  )
  Project.create!(
    name: Faker::Superhero.name.tr(" ", "-").underscore.dasherize,
    token: Faker::Alphanumeric.alpha(number: 10),
    account_id: account.id,
  )
end

10.times do |index|
  email = Faker::Internet.email.tr("_", "-")
  password = Faker::Internet.password(min_length: 6, max_length: 8)
  user = User.create!(
    email: email,
    password: password,
    confirmed_at: Date.new,
  )
  Project.create!(
    name: Faker::Superhero.name.tr(" ", "-").underscore.dasherize,
    token: Faker::Alphanumeric.alpha(number: 10),
    account_id: user.account.id,
  )
  organization = Organization.find(organization_ids[Faker::Number.between(from: 0, to: 3)])
  user.add_role(:admin, organization)
  puts "email: #{email}"
  puts "password: #{password}"
end
