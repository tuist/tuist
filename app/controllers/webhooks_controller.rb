# frozen_string_literal: true

class WebhooksController < ActionController::Base
  protect_from_forgery except: [:stripe, :okta] # Disable CSRF protection for this endpoint

  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    event = nil

    begin
      logger.debug("Received Stripe event: #{payload.inspect}")

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
    when 'customer.subscription.updated', 'customer.subscription.created', 'customer.subscription.deleted'
      subscription = event.data.object # contains a Stripe::PaymentIntent
      StripeUpdateSubscriptionService.call(subscription: subscription)
    else
      puts "Unhandled event type: #{event.type}"
    end

    head(:ok)
  end

  # https://developer.okta.com/docs/concepts/event-hooks/#one-time-verification-request
  # Okta sends a verification request to ensure that the service is ready to process
  # webhooks.
  def okta_verify
    okta_verification_challenge = request.headers["x-okta-verification-challenge"]
    if okta_verification_challenge.blank?
      head(:bad_request)
    else
      render(json: { "verification" => okta_verification_challenge }, status: :ok)
    end
  end

  # https://developer.okta.com/docs/concepts/event-hooks/
  def okta
    authorization_header = request.headers["authorization"]
    expected_authorization_header = Environment.okta_event_hook_secret
    is_valid = !authorization_header.blank? &&
      !expected_authorization_header.blank? &&
      ActiveSupport::SecurityUtils.secure_compare(
        authorization_header,
        expected_authorization_header,
      )
    if is_valid
      begin
        body = request.body.read
        payload = JSON.parse(body)
        logger.info("Received Okta event: #{payload.inspect}")
        payload["data"]["events"].select do |event|
          event["eventType"] == "application.user_membership.remove"
        end.each do |event|
          is_tuist_cloud_app = event["target"].select do |t|
                                 t["type"] == "AppInstance"
                               end.map { |t| t["id"] }.include?(Environment.okta_client_id)
          next unless is_tuist_cloud_app

          # Target includes three elements: AppUser, AppInstance, User
          #   - The first one is who performs the action
          #   - The second one is the app instance it performs the action for
          #   - The third one is the user it performs the action on
          user_ids = event["target"].select { |t| t["type"] == "User" }.map { |t| t["id"] }
          DestroyOauth2Users.call(ids: user_ids, provider: "okta")
        end
        head(:ok)
      rescue JSON::ParserError
        head(:bad_request)
      end

    else
      head(:bad_request)
    end
  end
end
