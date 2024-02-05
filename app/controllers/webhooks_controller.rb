# frozen_string_literal: true

class WebhooksController < ActionController::Base
  protect_from_forgery except: :stripe # Disable CSRF protection for this endpoint

  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    event = nil

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, Environment.stripe_endpoint_secret
      )
    rescue JSON::ParserError
      # Invalid payload
      return head(:bad_request)
    rescue Stripe::SignatureVerificationError => e
      # Invalid signature
      puts "Error verifying webhook signature: #{e.message}"
      return head(:unauthorized)
    end

    # Handle the event
    case event.type
    when 'customer.subscription.updated'
      subscription = event.data.object # contains a Stripe::PaymentIntent
      StripeUpdateSubscriptionService.call(subscription: subscription)
    else
      puts "Unhandled event type: #{event.type}"
    end

    head(:ok)
  end
end
