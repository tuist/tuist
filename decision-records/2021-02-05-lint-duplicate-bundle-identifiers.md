# Linting Duplicate Bundle Identifiers

## Date: 05/02/2021

## Reference Issues or Discussions:

* https://github.com/tuist/tuist/discussions/2423
* https://github.com/tuist/tuist/issues/2443

## Contributors Involved:

[@natanrolnik](https://github.com/natanrolnik)
[@marekfort](https://github.com/fortmarek)
[@kwridan](https://github.com/kwridan)

## Explanation

Natan had an experience where, by mistake, two targets had the same bundle identifier. The error was found only when Xcode was about to run the application in the iOS Simulator. This is a classic case where Tuist could add as a safety net for developers, and catch the error before Xcode, thus saving time to the user. 

The implementation should skip cases where variables are used in the bundle identifier, as in `${BUNDLE_ID_PREFIX}.${PRODUCT_NAME:rfc1034identifier}`, for example.