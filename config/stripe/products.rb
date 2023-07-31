# This file contains descriptions of all your stripe products

# Example
# Stripe::Products::PRIMO #=> 'primo'

# Stripe.product :primo do |product|
#   # product's name as it will appear on credit card statements
#   product.name = 'Acme as a service PRIMO'
#
#   # Product, either 'service' or 'good'
#   product.type = 'service'
# end

# Once you have your products defined, you can run
#
#   rake stripe:prepare
#
# This will export any new products to stripe.com so that you can
# begin using them in your API calls.
