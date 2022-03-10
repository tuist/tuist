import React, { useState } from 'react';
import {
  Page,
  Card,
  FormLayout,
  TextField,
  AppProvider,
  Checkbox,
  Stack,
} from '@shopify/polaris';

interface LoginProps {
  omniauthProviders: [{ title: string; link: string }];
  authenticityToken: string;
  signUpURL: string;
}

interface PostButtonProps {
  href: string;
  method?: 'post' | 'get';
  children: JSX.Element | string;
}

const LinkButton = ({ href, children, method }: PostButtonProps) => {
  return (
    <a
      className="Polaris-Button"
      href={href}
      data-polaris-unstyled="true"
      data-method={method ?? 'get'}
    >
      <span className="Polaris-Button__Content">
        <span className="Polaris-Button__Text">{children}</span>
      </span>
    </a>
  );
};

const Login = ({
  omniauthProviders,
  authenticityToken,
  signUpURL,
}: LoginProps) => {
  const theme = {
    logo: {
      width: 124,
      topBarSource:
        'https://cdn.shopify.com/s/files/1/0446/6937/files/jaded-pixel-logo-color.svg?6215648040070010999',
      contextualSaveBarSource:
        'https://cdn.shopify.com/s/files/1/0446/6937/files/jaded-pixel-logo-gray.svg?6215648040070010999',
      url: 'http://jadedpixel.com',
      accessibilityLabel: 'Jaded Pixel',
    },
  };
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [rememberMe, setRememberMe] = useState(false);
  return (
    <AppProvider
      theme={theme}
      i18n={{
        Polaris: {
          Avatar: {
            label: 'Avatar',
            labelWithInitials: 'Avatar with initials {initials}',
          },
          ContextualSaveBar: {
            save: 'Save',
            discard: 'Discard',
          },
          TextField: {
            characterCount: '{count} characters',
          },
          TopBar: {
            toggleMenuLabel: 'Toggle menu',
          },
          Modal: {
            iFrameTitle: 'body markup',
          },
          Frame: {
            skipToContent: 'Skip to content',
            navigationLabel: 'Navigation',
            Navigation: {
              closeMobileNavigationLabel: 'Close navigation',
            },
          },
        },
      }}
    >
      <Page title="Sign in to Tuist Cloud">
        <Card sectioned>
          <Card.Section title="Email login">
            <FormLayout>
              <TextField
                type="email"
                label="Email"
                name="user[email]"
                value={email}
                onChange={(newValue) => {
                  setEmail(newValue);
                }}
              />
              <TextField
                type="password"
                label="Password"
                name="user[password]"
                value={password}
                onChange={(newValue) => {
                  setPassword(newValue);
                }}
              />
              <Stack alignment="center">
                <LinkButton
                  href={`/users/sign_in?user[email]=${email}&user[password]=${password}&authenticity_token=${authenticityToken}&remember_me=${Number(
                    rememberMe,
                  )}`}
                  method="post"
                >
                  Log in
                </LinkButton>
                <Checkbox
                  label="Remember me?"
                  checked={rememberMe}
                  onChange={(newValue) => {
                    setRememberMe(newValue);
                  }}
                />
              </Stack>
              <Stack alignment="center">
                <LinkButton
                  href={
                    signUpURL +
                    `?email=${email}&password=${password}&authenticity_token=${authenticityToken}`
                  }
                >
                  Sign up
                </LinkButton>
                <LinkButton href="/users/confirmation/new">
                  Didn't receive confirmation instructions?
                </LinkButton>
              </Stack>
            </FormLayout>
          </Card.Section>
          <Card.Section title="Social login">
            <Stack vertical={false}>
              {omniauthProviders.map((provider) => {
                return (
                  <LinkButton
                    href={provider.link}
                    key={provider.title}
                    method="post"
                  >
                    {provider.title}
                  </LinkButton>
                );
              })}
            </Stack>
          </Card.Section>
        </Card>
      </Page>
    </AppProvider>
  );
};

export default Login;
