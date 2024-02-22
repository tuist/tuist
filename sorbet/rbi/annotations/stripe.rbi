# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

class Stripe::APIResource < Stripe::StripeObject
  Elem = type_member { { fixed: T.untyped } }

  sig { returns(Stripe::APIResource) }
  def refresh; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def id; end

  # not all objects, at all times have metadata (deleted customers for instance)
  # @method_missing: from StripeObject
  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  def metadata; end

  # @method_missing: from StripeObject
  sig { params(val: T::Hash[T.any(String, Symbol), T.untyped]).void }
  def metadata=(val); end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::APIResource) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::ApplicationFee < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def id; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def refunds; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::ApplicationFee) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::BalanceTransaction < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def type; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def currency; end

  # if resource is expanded, the actual object is returned
  # @method_missing: from StripeObject
  sig { returns(T.any(String, Stripe::Charge, Stripe::Refund)) }
  def source; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def fee; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def net; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[T.untyped, T.untyped])).returns(Stripe::BalanceTransaction) }
  def self.retrieve(id, opts = {}); end
end

class Stripe::BankAccount < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def fingerprint; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def bank_name; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def routing_number; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def last4; end
end

class Stripe::Card < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def brand; end

  # @method_missing: from StripeObject
  sig { params(other: String).returns(String) }
  def brand=(other); end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def country; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def exp_month; end

  # @method_missing: from StripeObject
  sig { params(other: Integer).returns(Integer) }
  def exp_month=(other); end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def exp_year; end

  # @method_missing: from StripeObject
  sig { params(other: Integer).returns(Integer) }
  def exp_year=(other); end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def last4; end

  # @method_missing: from StripeObject
  sig { params(other: String).returns(String) }
  def last4=(other); end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[T.untyped, T.untyped])).returns(Stripe::Card) }
  def self.retrieve(id, opts = {}); end
end

class Stripe::Charge < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def refunds; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount_captured; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(T.any(Stripe::Source, Stripe::Card))) }
  def source; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def failure_message; end

  # @method_missing: from StripeObject
  sig { returns(T.any(Stripe::Dispute, String)) }
  def dispute; end

  # @method_missing: from StripeObject
  sig { returns(T::Boolean) }
  def captured; end

  # @method_missing: from StripeObject
  sig { returns(T::Boolean) }
  def refunded; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(T.any(String, Stripe::ApplicationFee))) }
  def application_fee; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(Stripe::BalanceTransaction)) }
  def balance_transaction; end

  # @method_missing: from StripeObject
  sig { returns(T::Boolean) }
  def paid; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def status; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def currency; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def statement_descriptor; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def description; end

  # @method_missing: from StripeObject
  sig { returns(T.any(String, Stripe::PaymentIntent)) }
  def payment_intent; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(T.any(String, Stripe::Customer))) }
  def customer; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[T.untyped, T.untyped])).returns(Stripe::Charge) }
  def self.retrieve(id, opts = {}); end
end

class Stripe::Coupon < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def name; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Coupon) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::CreditNote < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def total; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def voided_at; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(Integer)) }
  def out_of_band_amount; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def currency; end

  # @method_missing: from StripeObject
  sig { returns(T.any(String, Stripe::Customer)) }
  def customer; end

  # @method_missing: from StripeObject
  sig { returns(T.any(String, Stripe::Invoice)) }
  def invoice; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def lines; end

  # @method_missing: from StripeObject
  sig { returns(T::Array[T.untyped]) }
  def tax_amounts; end

  # @method_missing: from StripeObject
  sig { returns(T::Array[T.untyped]) }
  def discount_amounts; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(Stripe::CustomerBalanceTransaction)) }
  def customer_balance_transaction; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(Stripe::Refund)) }
  def refund; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::CreditNote) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::CreditNoteLineItem < Stripe::StripeObject
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def currency; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def quantity; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def invoice_line_item; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def type; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def description; end
end

class Stripe::Customer < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def default_source; end

  # @method_missing: from StripeObject
  sig { params(arg: String).void }
  def default_source=(arg); end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def sources; end

  # @method_missing: from StripeObject
  sig { params(token: String).void }
  def payment_method=(token); end

  # @method_missing: from StripeObject
  sig { params(settings: T::Hash[Symbol, T.untyped]).void }
  def invoice_settings=(settings); end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def name; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def account_balance; end

  # @method_missing: from StripeObject
  sig { params(arg: Integer).void }
  def account_balance=(arg); end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def subscriptions; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def email; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.any(String, T::Array[String])]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Customer) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::CustomerBalanceTransaction < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def credit_note; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def currency; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def customer; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def ending_balance; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def invoice; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def type; end
end

class Stripe::Discount < Stripe::StripeObject
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(Stripe::Coupon) }
  def coupon; end
end

class Stripe::Dispute < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def balance_transaction; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount; end

  # @method_missing: from StripeObject
  sig { returns(T::Array[Stripe::BalanceTransaction]) }
  def balance_transactions; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Dispute) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::Event < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def type; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::StripeObject) }
  def data; end

  # @method_missing: from StripeObject
  sig { returns(T::Boolean) }
  def livemode; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Event) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::Invoice < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(T.nilable(Stripe::PaymentIntent)) }
  def payment_intent; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount_paid; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def status; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def customer; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def lines; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def currency; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def total; end

  # @method_missing: from StripeObject
  sig { returns(T.any(String, Stripe::Charge)) }
  def charge; end

  # @method_missing: from StripeObject
  sig { returns(T::Boolean) }
  def paid; end

  # @method_missing: from StripeObject
  sig { params(other: T::Boolean).void }
  def paid=(other); end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def billing; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def subtotal; end

  # @method_missing: from StripeObject
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def status_transitions; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Invoice) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::InvoiceItem < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(T.nilable(Stripe::Plan)) }
  def plan; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def description; end

  # @method_missing: from StripeObject
  sig { returns(T.any(Stripe::Customer, String)) }
  def customer; end

  # @method_missing: from StripeObject
  sig { returns(T.any(Stripe::Invoice, String)) }
  def invoice; end

  # unsure how to represent a StripeObject with specific keys/mmethods without causing typing errors
  # @method_missing: from StripeObject
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def period; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::InvoiceItem) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::File < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def purpose; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def type; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(Integer)) }
  def expires_at; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def filename; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def links; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def size; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def title; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def url; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::File) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::ListObject
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(T::Array[T.untyped]) }
  def data; end

  # @method_missing: from StripeObject
  sig { returns(T::Boolean) }
  def has_more; end
end

class Stripe::PaymentIntent < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def client_secret; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def status; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def charges; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def line_items; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.any(String, T::Array[String])]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::PaymentIntent) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::PaymentMethod < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(Stripe::Card) }
  def card; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def type; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::PaymentMethod) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::Payout < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def arrival_date; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.any(String, T::Array[String])]), opts: T.nilable(T::Hash[T.untyped, T.untyped])).returns(Stripe::Payout) }
  def self.retrieve(id, opts = {}); end
end

class Stripe::Plan < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # unsure how to represent a StripeObject with specific keys/mmethods without causing typing errors
  # @method_missing: from StripeObject
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def period; end

  # @method_missing: from StripeObject
  sig { returns(T.any(String, Stripe::Product)) }
  def product; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Plan) }
  def self.retrieve(id, opts = {}); end
end

class Stripe::Product < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def name; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def description; end

  # @method_missing: from StripeObject
  sig { returns(T::Boolean) }
  def shippable; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Product) }
  def self.retrieve(id, opts = {}); end
end

class Stripe::Refund < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def charge; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def amount; end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(T.any(String, Stripe::CreditNote))) }
  def credit_note; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def currency; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def created; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.any(String, T::Array[String])]), opts: T.nilable(T::Hash[T.untyped, T.untyped])).returns(Stripe::Refund) }
  def self.retrieve(id, opts = {}); end
end

class Stripe::Source < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Source) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::StripeError
  sig { returns(T.nilable(String)) }
  def message; end

  sig { returns(T.nilable(String)) }
  def code; end
end

class Stripe::StripeObject
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(T.any(Stripe::Subscription, Stripe::Customer, Stripe::Invoice)) }
  def object; end

  sig { params(key: T.any(String, Symbol)).returns(T.untyped) }
  def [](key); end
end

class Stripe::Subscription < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { params(val: T::Array[T::Hash[Symbol, T.untyped]]).void }
  def items=(val); end

  # @method_missing: from StripeObject
  sig { params(val: T.any(String, ::Stripe::Customer)).void }
  def customer=(val); end

  # @method_missing: from StripeObject
  sig { params(val: String).void }
  def payment_behavior=(val); end

  # @method_missing: from StripeObject
  sig { params(val: Integer).void }
  def trial_end=(val); end

  # @method_missing: from StripeObject
  sig { returns(T.nilable(T.any(T.nilable(Stripe::Invoice), T.nilable(String)))) }
  def latest_invoice; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Subscription) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::TaxRate < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(T.nilable(String)) }
  def description; end

  # @method_missing: from StripeObject
  sig { returns(String) }
  def display_name; end

  # @method_missing: from StripeObject
  sig { returns(Integer) }
  def percentage; end
end

class Stripe::Token < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(String) }
  def type; end

  # @method_missing: from StripeObject
  sig { returns(Stripe::BankAccount) }
  def bank_account; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Token) }
  def self.retrieve(id, opts = nil); end
end

class Stripe::Transfer < Stripe::APIResource
  Elem = type_member { { fixed: T.untyped } }

  # @method_missing: from StripeObject
  sig { returns(Stripe::ListObject) }
  def reversals; end

  sig { params(id: T.any(String, T::Hash[Symbol, T.untyped]), opts: T.nilable(T::Hash[Symbol, T.untyped])).returns(Stripe::Transfer) }
  def self.retrieve(id, opts = nil); end
end
