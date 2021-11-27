# frozen_string_literal: true

# rubocop:disable Output

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

4.times do |index|
  Faker::Config.random = Random.new(index)
  organization = Organization.create!
  Account.create!(
    name: Faker::Superhero.name,
    owner: organization
  )
end

10.times do |index|
  Faker::Config.random = Random.new(index)
  email = Faker::Internet.email
  password = Faker::Internet.password(min_length: 6, max_length: 8)
  user = User.create!(
    email: email,
    password: password,
    confirmed_at: Date.new
  )
  Account.create!(
    name: email.split(/@/, 2).first,
    owner: user
  )
  organization = Organization.find(Faker::Number.between(from: 1, to: 4))
  user.add_role(:user, organization)
  puts "email: #{email}"
  puts "password: #{password}"
end

14.times do |index|
  Faker::Config.random = Random.new(index + 10)
  Project.create!(
    name: Faker::Superhero.name.tr(" ", "-").underscore.dasherize,
    token: Faker::Alphanumeric.alpha(number: 10),
    account_id: index + 1
  )
end
