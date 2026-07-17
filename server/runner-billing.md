# Runner billing

Runner usage is billed by machine shape. A shape is the platform, processor
count, and memory allocation. Fleets, physical hosts, runner images, and Xcode
versions do not create separate billing dimensions when those resources are
the same.

Tuist records exact runtime in milliseconds and reports gross usage to Stripe.
Stripe owns the list price, invoice calculation, and prepaid discount. Tuist
does not maintain a monetary balance or subtract prepaid minutes.

The `vcpu` segment in the stable event names means
[virtual central processing unit](https://en.wikipedia.org/wiki/Virtual_CPU),
and `gb` means [gigabyte](https://en.wikipedia.org/wiki/Gigabyte).

## Machines currently offered

| Platform | Processors | Memory | Stripe meter event name |
| --- | ---: | ---: | --- |
| Linux | 1 | 2 gigabytes | `runner_linux_1_vcpu_2_gb_milliseconds` |
| Linux | 2 | 4 gigabytes | `runner_linux_2_vcpu_4_gb_milliseconds` |
| Linux | 2 | 8 gigabytes | `runner_linux_2_vcpu_8_gb_milliseconds` |
| Linux | 4 | 8 gigabytes | `runner_linux_4_vcpu_8_gb_milliseconds` |
| Linux | 4 | 16 gigabytes | `runner_linux_4_vcpu_16_gb_milliseconds` |
| Linux | 8 | 16 gigabytes | `runner_linux_8_vcpu_16_gb_milliseconds` |
| Linux | 8 | 32 gigabytes | `runner_linux_8_vcpu_32_gb_milliseconds` |
| Linux | 16 | 32 gigabytes | `runner_linux_16_vcpu_32_gb_milliseconds` |
| macOS | 6 | 14 gigabytes | `runner_macos_6_vcpu_14_gb_milliseconds` |

`Tuist.Runners.Billing.billable_machines/0` derives this list from the runner
catalog, including any operator-defined Linux pool with a distinct shape.

## Stripe setup

1. Create one product named `Runner compute`.
2. Create one [meter](https://docs.stripe.com/billing/subscriptions/usage-based/meters/configure)
   for every row above. Use the exact event name and `Sum` aggregation.
3. Create one monthly, recurring, metered Price per meter under that product.
   Attach the corresponding meter, divide the aggregate quantity by `60,000`,
   round up, and set the normal per-minute amount for that machine.
4. Put the resulting Price identifiers in each environment's Helm values:

   ```yaml
   server:
     stripe:
       prices:
         runners:
           runner_linux_1_vcpu_2_gb_milliseconds: price_...
           runner_linux_2_vcpu_4_gb_milliseconds: price_...
           runner_linux_2_vcpu_8_gb_milliseconds: price_...
           runner_linux_4_vcpu_8_gb_milliseconds: price_...
           runner_linux_4_vcpu_16_gb_milliseconds: price_...
           runner_linux_8_vcpu_16_gb_milliseconds: price_...
           runner_linux_8_vcpu_32_gb_milliseconds: price_...
           runner_linux_16_vcpu_32_gb_milliseconds: price_...
           runner_macos_6_vcpu_14_gb_milliseconds: price_...
   ```

The server adds every configured runner Price as a subscription item whenever
it creates or changes a plan. Existing subscriptions must receive the same
items once before runner billing is enabled for those accounts. Nine runner
items plus the current plan items remain below Stripe's
[20-item limit for a standard subscription](https://docs.stripe.com/billing/subscriptions/usage-based/advanced/compare).

## Prepaid discount

Sell prepaid access as money, not as machine minutes. After a prepaid invoice
is paid, create a [Stripe billing credit grant](https://docs.stripe.com/billing/subscriptions/usage-based/billing-credits/implementation-guide)
in the subscription's currency and restrict its eligibility to the runner
metered Prices.

For a discount fraction `d` and payment `p`, grant `p / (1 - d)`. For example,
a customer paying 80 currency units for a 20 percent discount receives 100
currency units of runner credit. A minute on every machine is therefore 20
percent cheaper while each machine keeps its own normal per-minute rate.

Create the grant only after the prepaid invoice is paid. Stripe then consumes
the grant against eligible runner usage before charging the remaining invoice
balance. Usage reporting stays identical for prepaid and pay-as-you-go
customers.
