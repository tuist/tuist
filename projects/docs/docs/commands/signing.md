---
title: tuist signing
slug: '/commands/signing'
description: 'Tuist offers a deterministic, pain-free solution to signing. Read on if you would like to learn more about how it works and how you can set it up.'
---

Signing is one of the most complicated things that developers have to deal with
when working with Xcode. While Xcode does offer an option of automatic signing,
most teams choose not to use it since it creates an unmanageable mess in their team accounts.
But manually working with signing artifacts is tedious, error-prone and tools
automating this process are often non-deterministic and you still have to manually change
settings of your Xcode projects.

Tuist aims to solve all of the above pain points in a simple and _deterministic_ interface.

### How to Get Started

As the first step, download all your provisioning profiles that you'll need.
Once you downloaded them, make sure to rename the provisioning profiles, so they abide by the following convention:
`Target.Configuration.mobileprovision` for iOS apps or `Target.Configuration.provisionprofile` for macOS apps.
Where `Target` should be a name of the target, `Configuration` a name of the configuration.
Export the public (as .cer file) and private key (as .p12 file with an empty string as a password) from your keychain. Use the same basename for these two files: `SomeName.cer` and `SomeName.p12` - this name doesn't need to match any target or configuration.
If multiple provisioning profiles use the same certificate, it's fine to have `.p12` and `.cer` files just once in the folder - Tuist will find the matching one based on information embedded into the provisioning profile.
Now you can put all those files in `Tuist/Signing` directory within your project.
To make it all work, create a secure encryption by running the following command and placing its contents into `Tuist/master.key`.

```bash
openssl rand -base64 32
```

The key will be used for encrypting and decrypting your files.

After that, feel free to run `tuist generate` and everything else should be done for you -
that means, yes, also build settings!

### Additional commands

`tuist generate` automatically encrypts all signing artifacts.
If you want to decrypt your signing files,
feel free to run `tuist signing decrypt`.
To re-encrypt them run `tuist signing encrypt` (note that encryption is done automatically in `tuist generate`)

### Vendor

In the future we plan to also automate creating provisioning profiles and certificates.
Just by running `tuist vendor` and `tuist generate` will get you all setup,
nothing else needed!
