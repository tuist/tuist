---
title: Contributing
slug: '/cloud/contributing'
description: 'Learn how to contribute to Tuist Cloud.'
---

Tuist is an opensource project first and foremost. We are driven by the community and Tuist Cloud is no exception. However, to get both the development and production app running, we rely on a couple of services encrypted with a `master.key` that we can't share with every contributor.

That being said, we still want you to be able to contribute. This guide goes through what you need to do to get set up.

## Getting started

The first thing you'll need to do is to check out tuist if you don't have it locally:
```bash
git clone https://github.com/tuist/tuist
```

And then navigate to the cloud project:
```bash
cd tuist/projects/cloud
```

Once you're in the cloud directory, you can run `./up`. This script will install the necessary dependencies, set up a new `master.key` if you don't have one already, and create a new `credentials.yml` file that you will be able to start editing right away.

The file `credentials.yml.enc` showcases what credentials you might need. That being said, you might _not_ need all of them, depending on what you want to do.

To get you started with some pre-generated accounts, you can run:
```bash
bin/rails db:seed
```

You should see the account names with their passwords – you can use those in the login page. Before running a server locally, you will also need to set up AWS – this is the only service you _must_ set up. Learn more about how to do that below.

## AWS

[AWS](https://aws.amazon.com/) is our current storage of choice. Tuist Cloud receives cached framework from the `tuist` CLI and saves them in AWS – and vice-versa, it serves cached frameworks from the AWS to the `tuist` CLI.

For Tuist Cloud, we need two things: `access_key_id` and `secret_access_key`. Once you sign up to AWS, you can follow [this](https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html) guide to obtain the necessary credentials.

## Run the dev server

It's time to run our `dev` server 🎉

You can run `./dev` and this will spin up a local instance at http://127.0.0.1:3000. You can navigate from the landing page to the `Login` and use one of the credentials from the `bin/rails db:seed` command to log in. You should now be able to create a new project that will be saved in your local database!

If you want to test out the sign up or Github login flow, you will need to additionally set up for [devise](https://github.com/heartcombo/devise) and [mailgun](https://www.mailgun.com/). Read on for more details.

## Mailgun

We use