---
title: "Keeping your Swift apps' sensitive data secret"
category: "learn"
tags: ["ci", "automation"]
excerpt: "Learn how to safely share and use sensitive data in your Swift apps."
author: pepicrft
---

When you build Swift apps,
you might need to use or include sensitive data within your app.
For example, API keys, or the certificate for signing the app.
This is information that you don't want to include raw in your repository.
What most teams do is include it as a secret in their CI/CD environment,
and read its value through environment variables.
However,
if the need for debugging automation arises,
this makes debugging automation a bit more difficult,
since a trusted subject (e.g. the lead of the team) can't easily access the values.

[Fastlane Match](https://docs.fastlane.tools/actions/match/) proposed a solution for this in the context of certificates and provisioning profiles.
What if they are encrypted under a private key in the same repository or in a separate repository that all the developers have access to?
This is an approach similar to [credentials](https://guides.rubyonrails.org/security.html#custom-credentials) in [Ruby on Rails](https://rubyonrails.org/), which allows having a YAML file with encrypted values that the framework can automatically decrypt and expose at runtime when a private key is available.
Wouldn't it be awesome if we could generalize Match's approach to work not only with certificates and provisioning profiles,
but also with other sensitive data?
Let us tell you that this is indeed possible thanks to [Mise](/blog/2025/02/04/mise), a tool that we already talked about in the past.
We'll guide you through how to set it up, and give you some examples of how to use it to encrypt certificates, and expose and obfuscate information into your apps. Let's dive right into it!

##  Setting up your "secret" environment

[Mise](https://mise.jdx.dev/) is a frontend to your dev env. It might be the first time that you might have heard of this concept, but you can think of it as a tool that takes care of the things that you need for development, from provisioning the environment with the tools that your project needs, to dynamically configuring the environment with environment variables that you need to work on the project.

One of the features that they provide is [secrets](https://mise.jdx.dev/environments/secrets.html). They can decrypt secrets that are encrypted using a private key, and expose them in the environment as environment variables. The solution builds upon [sops](https://getsops.io/), a tool that solves encrypting and decrypting configuration files (e.g., YAML, ENV, JSON), and [age](https://github.com/FiloSottile/age), a tool to generate keypairs to use with sops.

The first thing that we'll need to do is installing both sops and age. We recommend pinning the version in your project's `mise.toml` file instead of installing them globally. Edit the file, and add the tools under the `tools` section:

```toml
[tools]
# ...Other tools
"sops" = "3.9.3"
"age" = "1.2.1"
```

Then run `mise install` to install the tools and make them available. The next step is to generate the keypair that we'll use to encrypt secrets. Run the following command:

```bash
age-keygen -o ~/.config/mise/my-project-age.txt
```

We recommend prefixing the key with the name of your project or organization such that you can have multiple keys in your environment that can have a very granular scope, for example a single project, or a more generic organization-wide key. The command will output a file containing the private and the public key:

```bash
# created: 2025-04-03T10:30:44+02:00
# public key: age16wnlakxsqk6k627jn5vuv3kk75jdnfpn5eg8sghrw0yj6ehxlsgqx864sd
AGE-SECRET-KEY-1F7VFL7PF90Z2TEMKTXX9KJR5LUVNR45T7W3586WJKUME40JXQUCS9EKGN8
```

The last line represents your private key so keep it in a secure place and make sure you only expose it in trusted environments.

Once we have the key, the next thing we'll need is a file that will contain the secrets that we want to encrypt, and a couple of scripts to encrypt the file and edit the encrypted content. Let's start with the file containing the secrets by creating a `.env.json` file at the root with an empty JSON object:

```json
{}
```

Then we are going to create two [Mise tasks](https://mise.jdx.dev/tasks/) for encrypting and editing. The first one will be at `mise/tasks/env/encrypt.sh`. Create the file with the following content:

```bash
#!/usr/bin/env bash
# mise description="Encrypts the .env file"

set -eo pipefail

sops encrypt -i --age "age16wnlakxsqk6k627jn5vuv3kk75jdnfpn5eg8sghrw0yj6ehxlsgqx864sd" .env.json
```

Where the value passed through `--age` is the public key generated. Make sure you replace it with yours. The second task will be at `mise/tasks/env/edit.sh`:

```bash
#!/usr/bin/env bash
# mise description="Edit the .env file"

set -eo pipefail

SOPS_AGE_KEY_FILE=~/.config/mise/my-project-age.txt sops edit .env.json
```

Similarly, make sure that `SOPS_AGE_KEY_FILE` points to the file where you've decided to persist the key in development environments.

Make sure that you set executable permissions for the `encrypt.sh` and `edit.sh` scripts:

```bash
chmod +x mise/tasks/env/encrypt.sh
chmod +x mise/tasks/env/edit.sh
```

And then run `mise run env:encrypt` to encrypt the `.env.json` file. The last step needed to expose the secrets as environment variables is to add the following configuration to the `mise.toml` file:

```toml
[env]
_.file = ".env.json"

[settings]
sops.age_key_file = "~/.config/mise/my-project-age.txt" # The path to your key
```

Mise will automatically decrypt and expose the content from `.env.json` into the environment, so you can access the secrets using env. variables.

## Editing the encrypted file

You might have noticed that we added a Mise task called `env:edit` to edit the encrypted file. Run the following command to edit the file:

```bash
EDITOR="code --wait" mise run env:edit
```

You can replace `code` with your editor of choice (e.g. `zed`, `cursor`). The task will open the editor with an unencrypted version of the file and block the process until the edition finishes. On close, the process will then encrypt your changes automatically. Isn't that magic? Try to add some content to it, save it, and then close. For example:

```json
{
  "HELLO": "WORLD"
}
```

If you then run `echo $HELLO`. You'll notice that the variable is exposed in the environment.

## Continuous integration

Alright, we've got a setup to encrypt, decrypt, and edit sensitive data, which works if we have a key in the file-system, but what about CI environments where the key is not available in a file. In those environments you'll have to expose it as an environment variable `MISE_SOPS_AGE_KEY`. Just copy the value, and expose it in trusted CI environments. We recommend that you only do it in the steps that need to access the sensitive data to reduce the security risk.
When invoking your automation through Mise tasks, you can assume the environment variables will be present:

```bash
mise run release
```

There's an interesting side effect of using this approach to encrypting secrets. As we touched on in [Own your Swift apps' automation](/blog/2025/03/11/own-your-automation), secret management is one of the features that CI providers offer and that creates vendor lock-in with them.
Thanks to this, you can reduce the number of secrets that you expose to just one, the sops private key,
and not only that, but you can use Git to keep track of the changes in the secrets. You won't see the value changes because they are encrypted, but you can use commit messages to track for example that "certificate x renovated due to expiration".
Git is a powerful tool that gives you a record of changes for free, so moving away from it is generally a bad idea.

## Use case 1 - Encrypting certificates

The most common use case for encrypting sensitive data is "certificates" that workflows might need to use for signing the app for distribution. As mentioned earlier, teams have traditionally used [Match](https://docs.fastlane.tools/actions/match/) for that and automating the generation of certificates and profiles. If you only need it for just encrypting files, you might not need Match at all.

As you probably know, the signing certificate, containing the public and the private key, is typically a `.p12` file. So how do we get that into our `.env.json` file if all we have is a file? Easy, you can Base64 its content:

```bash
base64 -o - -i /path/to/certificate.p12 | pbcopy
```

Ensure that when you export the certificate from the Keychain by doing right-click on the certificate, it also includes the private key. In Keychain's UI you'll notice if you click on the certificate it'll show a dropdown with the private key.

Once you have the certificate in the pasteboard, you can run the edit command, and then place it in the encrypted `.env.json` file:

```json
{
  "BASE_64_CERTIFICATE": "<BASE64_ENCODED_CERTIFICATE>",
  "CERTIFICATE_PASSWORD": "<PASSWORD>"
}
```

You can verify that the content is available by echoing it `echo $BASE_64_CERTIFICATE`.

The next step in the workflow that needs the certificate is to decode it and install it in the Keychain. If the script runs locally, you can use the default keychain. When that happens, you'll likely get a prompt from the system asking for your password to install the certificate. In CI, it's recommended to create a temporary keychain to avoid issues with prompts and permissions. You can use the following code snippet:

```bash
TMP_DIR=/private$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT # Delete on exit

if [ "${CI:-}" = "true" ]; then
    echo "Creating a temporary keychain"
    KEYCHAIN_PASSWORD=$(uuidgen)
    KEYCHAIN_PATH=$TMP_DIR/certificates/temp.keychain
    security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
    security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
    security default-keychain -s $KEYCHAIN_PATH
    security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
fi

echo $BASE_64_CERTIFICATE | base64 --decode > $TMP_DIR/certificate.p12 && security import $TMP_DIR/certificate.p12 -P $CERTIFICATE_PASSWORD -A
```

Note that the above step might be optional since some CI providers already do it for you.

That's really all you need. Xcode's build system, which uses the `codesign` tool internally, should be able to look up the certificate in the Keychain and use it for signing. Isn't it amazing that we replicated the core-most piece of functionality that Match provides?

## Use case 2 - Encrypting runtime data

The second common use case in app development is encrypting runtime data. For example, you've got an API key to initialize an SDK or interact with your backend services, and you don't want to include that raw in your app's `Info.plist`. You might want to obfuscate them, but how do you pass the environment variable all the way to the build system to obfuscate its value at build time?

First, you'll need a tool to obfuscate the data at compile-time so that the value can't be easily read from the binary. For that, you can use the [ObfuscateMacro](https://github.com/p-x9/ObfuscateMacro). Add it to your project as a dependency and then create a static value:

```swift
import ObfuscateMacro

struct Secrets {
  static let apiKey = #ObfuscatedString("SECRET_API_KEY")
}
```

Note in the code snippet that we hardcoded the value, which is not what we want. The secret is an environment variable, which we need to somehow pass to the compiler. Unfortunately, Xcode's build system nor Swift Macros have that capacity, therefore you'll have to run a script before the build process to generate the values. 

To simplify the process, we created [that script](https://gist.github.com/pepicrft/a692d44abf72df96c7bcd12c1e7bbc75) which does that automatically for all the environment variables whose name starts with `SECRET_`:

```bash
#!/usr/bin/env bash
# mise/tasks/env/generate-secrets.sh

set -eo pipefail

# Check if output file argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <output_file_path>"
  exit 1
fi

OUTPUT_FILE="$1"

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  echo 'import ObfuscateMacro'
  echo ''
  echo 'struct Secrets {'
} > "$OUTPUT_FILE"

env | while IFS='=' read -r key value; do
  if [[ "$key" == SECRET_* ]]; then
    base_key="${key#SECRET_}"
    camel_case_key="$(echo "$base_key" | awk '{
      split(tolower($0), parts, "_");
      result = parts[1];
      for (i = 2; i <= length(parts); i++) {
        result = result toupper(substr(parts[i],1,1)) substr(parts[i],2);
      }
      print result;
    }')"

    echo "  static let $camel_case_key = #ObfuscatedString(\"$value\")" >> "$OUTPUT_FILE"
  fi
done

echo '}' >> "$OUTPUT_FILE"
```

Create the script at `mise/tasks/env/generate-secrets.sh` and assign executable permissions with `chmod +x mise/tasks/env/generate-secrets.sh` and then invoke it with `mise run env:generate-secrets Sources/Secrets.swift`. Make sure you replace `Sources/Secrets.swift` with the path where you plan to keep your secrets, and the file is included in the project target from where you plan to read them. Note that you'll need a placeholder that you can run in development, so I recommend setting development values, and when doing releases, override using the script.

You'll then have to adjust the automation from secret environments to run the script before building the project:

```bash
# Generate the secrets file
# Build/archive the project
```

## Closing words

Note that this only covers part of the security. You'll have to make sure the information is not included in visible parts of the requests, for example the URL, making it easily accessible by any malicious actor.
You'd be surprised how many apps include sensitive data in their `Info.plist`, and how easy it is to impersonate them from a different application. Imagine populating [Firebase](https://firebase.google.com/) analytics pretending to be a different app.
Now you no longer have excuses to add an extra layer of safety to your apps. You won't regret it in the future.

> Check out [this repository](https://github.com/tuist/secrets-in-swift-app) which contains an Xcode project exemplifying this setup.

## Updates

- The post was updated on April 10th 2025 to suggest including the `generate-secrets.sh` script in the repo over piping the `curl` output through bash, which is unsafe.
