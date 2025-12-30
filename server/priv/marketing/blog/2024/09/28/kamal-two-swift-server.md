---
title: "Deploy your Swift on the Server apps with Kamal 2"
category: "learn"
tags: ["Swift", "Server", "Kamal", "Deployments"]
image_url: https://images.unsplash.com/photo-1457364887197-9150188c107b?q=80&w=2940&auto=format&fit=crop
excerpt: "In this blog post, you'll learn how to use Kamal 2 to deploy your Swift on the Server apps to your own server."
author: pepicrft
---

[Swift](https://www.swift.org/) is an amazing language.
Developers use it not only for building apps for Apple platforms,
but also to run them [on the browser](https://swiftwasm.org/) or [embedded systems](https://www.swift.org/blog/embedded-swift-examples/).
One of the platforms where developers were very excited to run Swift was the server.
This excitement led to the creation of frameworks like [Vapor](https://vapor.codes/) and [Hummingbird](https://github.com/hummingbird-project/hummingbird),
a [conference](https://www.serversideswift.info/),
and even Apple evolved the language to introduce features that are key in building highly-concurrent web applications,
like [structured concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency) and [Actors](https://developer.apple.com/documentation/swift/actor).
Did you know that the team behind [Things](https://culturedcode.com/things/) uses it for [server](https://x.com/ktosopl/status/1839664679720726839)?

If you are new to using Swift on the server,
one of the things you'll have to figure out is **how to and where deploy your app.**
Historically, there has been many options to deploy your app.
Some large-scale organizations resorted to tools like [Kubernetes](https://kubernetes.io/),
which provided them with a lot of flexibility to deploy, scale, and manage their apps, and an independence from cloud providers.
However, Kubernetes is not the easiest tool to use.
So if you are a solo developer or a small team, you might want to look for something simpler.

You could always get your own server, SSH into it, and manually set things up there,
but you want a system that is able to roll new versions out automatically ensuring there's no downtime.
This would be hard to achieve through a manual configuration.

Simpler and an automatic alternative those models were using platforms like [Heroku](https://heroku.com) or [Fly](https://fly.io) that made it easy to deploy your app.
They made it as easy as running a `git push` or `fly deploy` command against them server.
Those platforms are often referred to as PaaS (Platform as a Service).
Their developer experience is top-notch, but since they sit between you and the infrastructure,
you might have to pay an extra cost for the convenience they provide.
What if the great DX could be achieved without that extra cost?
That's the question that the [Basecamp Team](https://github.com/basecamp),
in their process of moving away from the cloud,
asked themselves when they created [Kamal](https://kamal-deploy.org/).
They started referring to it as *#nopaas*.

## What is Kamal?

Kamal is a Ruby-based CLI,
that can deploy containarized applications to your own SSH-accessible server.
All you need is an OCI-compliant (e.g. in a `Dockerfile`),
a registry to push and pull the image from,
and a server what can be accessed through SSH.
Kamal will take care of the rest with an intuitive and well thought-out CLI.

Don't let the Ruby part scare you.
You don't need to know Ruby to use Kamal.
All the configuration is done through a very intuitive [YAML](https://en.wikipedia.org/wiki/YAML)-based [configuration file](https://kamal-deploy.org/docs/configuration/overview/).

In this post, we'd like to guide you through the process of deploying a Swift on the Server app using Kamal to an infrastructure provider like [Hertzner](https://www.hetzner.com/).

## Installing Kamal

The first thing you'll need to do is to install Kamal.
If you have a Ruby setup already, for example to run [Fastlane](https://github.com/fastlane/fastlane),
you can use Ruby's `gem install kamal` command to install it.
Alternatively, as suggested in [the documentation](https://kamal-deploy.org/docs/installation/),
you can run it through a container, which eliminates the need to have Ruby installed on your machine:

```bash
alias kamal='podman run -it --rm -v "${PWD}:/workdir" -v "/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock" -e SSH_AUTH_SOCK="/run/host-services/ssh-auth.sock" -v /var/run/docker.sock:/var/run/docker.sock ghcr.io/basecamp/kamal:latest'
```

## Create a server on Hetzner

If you don't have a server yet, you can can create one on [Hetzner](https://www.hetzner.com/cloud/) or any other provider that gives you SSH access.

When you create a server, you'll be asked for the following information:

- **Location:** This will depend on where most of the request to your app will come from. In our case, we are going to select `eu-central` for the sake of this tutorial.
- **Image:** Select Ubuntu 20.04, although Kamal should work with other Linux distributions.
- **CPU:** Select the smallest one from either x86 or ARM64, which is enough for a small app.
- **Networking:** Select *Public IPv6*. Later on you can add a *Public IPv4* if you need.
- **SSH keys:** This is a very important part since it will allow you to access the server. If you don't have an SSH key yet, you can generate one following [this tutorial](https://community.hetzner.com/tutorials/add-ssh-key-to-your-hetzner-cloud).

There are a handful of other options, from which we recommend you to enable backups in case you need to restore the server.
Then scroll down to the bottom, give it a name, which in our case will be `swift-on-server`, and click on `Create & Buy Now`.
In a few seconds you'll have your server up and running with the IP addres to access to it.

Make sure you can access to it by running:

```bash
# Replacing /64 at the end with 1
# Example: ssh root@2a01:4f8:c013:44ae::1
ssh root@{ip-v6-address}
```

## Create a Swift on the Server app

If you don't have a Swift on the Server app yet, you'll need to create one.
You can follow either [this tutorial](https://docs.vapor.codes/getting-started/hello-world/) if you plan to use Vapor,
or [this other one](https://docs.hummingbird.codes/2.0/documentation/hummingbird/gettingstarted) if you plan to use Hummingbird.

Note that projects created by both frameworks include a `Dockerfile` ([Hummingbird](https://github.com/hummingbird-project/template/blob/main/Dockerfile) and [Vapor](https://github.com/vapor/template/blob/main/Dockerfile)) to build and run your apps.
This is a requirement for Kamal, so if your project doesn't have one, you'll need to create it using those as a reference.

To make sure your app runs fine when containerized, you can run it locally:

```bash
# You can use Docker instead of Podman if you prefer
podman build -t swift-on-server .
podman run -p 8080:8080 swift-on-server --port 8080
```

If those commands succeed, you should see a log indicating that the app is running in some port.

## Adding Kamal configuration

Once you have Kamal installed, a containarizable Swift on the Server app, and a server to deploy it to, you can start adding the Kamal configuration.
Create the file `config/deploy.yml` in your project with the following content:

```yaml
service: swift-on-server
image: my-user/swift-on-server
servers:
  - server-ip # Example: 2a01:4f8:c013:44ae::1
registry:
  username:
    - KAMAL_REGISTRY_USERNAME
  password:
    - KAMAL_REGISTRY_PASSWORD
builder:
  arch: arm64
proxy:
  app_port: 8080
  healthcheck:
    interval: 3
    path: /
    timeout: 3
```

You'll have to create a file at `.kamal/secrets` with the following content to indicate the environment variables that Kamal will use to read the registry credentials:

```yaml
KAMAL_REGISTRY_USERNAME=$KAMAL_REGISTRY_USERNAME
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
```

By default, Kamal will use the [hub.docker.com](https://hub.docker.com) registry to push and pull the image,
which is free for public images.
[GitHub](https://github.com/features/packages) and [DigitalOcean](https://digitalocean.com) also offer registries, so you can use them if you prefer ensuring that you set the `registry.server` URL in the configuration file.

Once you have the configuration file in place, you can run the following command to set up the server and accessories:

```bash
kamal setup
```

Once the server is setup, you can deploy your app by running:

```bash
kamal deploy
```

Once the app is deployed, you can access it by visiting the IP address of the server in your browser.
Remember that for IPv6 addresses, you'll have to wrap them in square brackets. For example: `http://[2a01:4f8:c013:44ae::1]`.

Isn't it awesome? 🤩 With a single command you can deploy new instances of your app without any downtime.
And not only that, you can use `kamal rollback` to roll back to a previeous version in case something goes wrong,
or `kamal app logs` to see the logs of the app in real-time.

```
  INFO [6d6940ce] Finished in 0.758 seconds with exit status 0 (successful).
App Host: 2a01:4f8:c013:44ae::1
2024-09-28T08:25:29.458868573Z 2024-09-28T08:25:29+0000 info SwiftOnServer : [HummingbirdCore] Server started and listening on 0.0.0.0:8080
2024-09-28T08:25:29.730502401Z 2024-09-28T08:25:29+0000 info SwiftOnServer : hb.request.id=407b3450aeb404662cfade84f76b5afb hb.request.method=GET hb.request.path=/ [Hummingbird] Request
2024-09-28T08:25:57.302865171Z 2024-09-28T08:25:57+0000 info SwiftOnServer : hb.request.id=407b3450aeb404662cfade84f76b5afc hb.request.method=GET hb.request.path=/ [Hummingbird] Request
2024-09-28T08:25:57.356775404Z 2024-09-28T08:25:57+0000 info SwiftOnServer : hb.request.id=407b3450aeb404662cfade84f76b5afd hb.request.method=GET hb.request.path=/favicon.ico [Hummingbird] Request
```

## Bonus

As a natural next step, you might want to set up a domain to point to the IP address of the server,
and configure the Kamal proxy to provide HTTPs automatically for your app.
For the latter, all you need to do is to add the following lines to the `config/deploy.yml` file:

```yaml
proxy:
  ssl: true
  host: my-swift-on-server.com
```

With the above configuration, Kamal will automatically request a certificate from [Let's Encrypt](https://letsencrypt.org/) and configure the proxy to serve your app through HTTPs.

## Closing words

At Tuist we love simplicity and automation,
and we believe that Kamal embodies that spirit for deployments.
When you are getting started,
or even if you are at the size of a company like [37Signals](https://37signals.com/),
the company behind Kamal,
you might want to keep your infrastructure engineering and financial costs low without compromising the developer experience.
We belive Kamal is unique in striking that balance,
and can help you stay focused on what you do best: building your Swift on the Server app.

Until next time 🚀
