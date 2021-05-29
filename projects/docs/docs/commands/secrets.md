---
title: Generate secrets
slug: '/commands/secrets'
description: "Learn how to use Tuist's secret command to generate cryptographically secure secret."
---

There are scenarios in which users might need to generate a secret key,
for example for the `master.key` file that is used to encrypt files like the signing certificates.
For those,
Tuist provides a command that generates a cryptographically secure secret:

```bash
tuist secret
```
