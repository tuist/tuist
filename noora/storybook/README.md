# Noora Storybook

Install Noora's JavaScript dependencies from the parent directory:

```sh
cd noora
aube install
```

Then set up and start Storybook:

```sh
cd storybook
mix setup
mix phx.server
```

Visit [localhost:4000](http://localhost:4000). Client-side custom elements are listed under **Web components**. Open the [Badge](http://localhost:4000/web_components/badge) or [Button](http://localhost:4000/web_components/button) story directly.
