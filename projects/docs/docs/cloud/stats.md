---
title: Helping Tuist
slug: '/cloud/stats'
description: Learn about Tuist Stats
---

### Sending usage statistics

Tuist sends some **anonymous** analytics events to track the usage of the tool.
Having statistics about Tuist's usage helps contributors to make informed decision and better prioritize future work.
For example, if a command is only used by 1% of the users, it might not get prioritized for enhancements in the future.

The implementation is open source, mainly in the [TuistAnalytics](https://github.com/tuist/tuist/tree/main/Sources/TuistAnalytics) target.
If you are thinking about adding another event, please remember that we would like to keep tracking minimal and unobtrusive.

The data is collected on a server implemented for the [Tuist Cloud](https://cloud.tuist.io/) and we track these stats only for users who use Tuist Cloud.

Users can opt out from Tuist stats setting the following environment variable:

```
TUIST_CONFIG_STATS_OPT_OUT=1
```
