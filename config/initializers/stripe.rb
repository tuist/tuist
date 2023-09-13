# frozen_string_literal: true

unless Environment.self_hosted?
  Stripe.api_key = Environment.stripe_api_key
end
