# This file contains descriptions of all your statically defined
# stripe coupons. You may wish to define unique one-off coupons
# elsewhere, but for ones you will use many times, and will be
# shared between users, this is a good place.

# Example
# Stripe::Coupons::Gold25 #=> 'gold25'

# Stripe.coupon :gold25 do |coupon|
#   # specify if this coupon is useable 'once', 'forever', or 'repeating'
#   coupon.duration = 'repeating'
#
#   # absolute amount, in cents, to discount
#   coupon.amount_off = 199
#
#   # what currency to interpret the coupon amount
#   coupon.currency = 'usd'
#
#   # how long will this coupon last? (only valid for duration of 'repeating')
#   coupon.duration_in_months = 6
#
#   # percentage off
#   coupon.percent_off = 25
#
#   UTC timestamp specifying the last time at which the coupon can be redeemed
#   coupon.redeem_by = (Time.now + 15.days).utc
#
#   # How many times can this coupon be redeemed?
#   coupon.max_redemptions = 10
# end
#
# Once you have your coupons defined, you can run
#
#   rake stripe:prepare
#
# This will export any new coupons to stripe.com so that you can
# begin using them in your API calls. Any coupons found that are not in this
# file will be left as-is.
