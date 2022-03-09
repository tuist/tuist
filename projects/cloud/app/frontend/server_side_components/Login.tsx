import React, { useState } from 'react';
import {
  Page,
  Card,
  FormLayout,
  TextField,
  Button,
  AppProvider,
  Form,
} from '@shopify/polaris';
import { Link, useNavigate } from 'react-router-dom';

interface LoginProps {
  omniauthProviders: [{ title: string; link: string }];
  authenticityToken: string;
  signUpURL: string;
}

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
      <Page title="Remote Cache">
        <Card title="S3 Bucket" sectioned>
          <Form
            autoComplete={true}
            action="/users/sign_in"
            onSubmit={() => {
              fetch('/users/sign_in', {
                method: 'post',
                headers: { 'X-CSRF-Token': authenticityToken },
              });
            }}
          >
            <input
              type="hidden"
              name="authenticity_token"
              value={authenticityToken}
            />
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
              <Button submit>Login</Button>
              <Button
                onClick={() => {
                  fetch(
                    signUpURL +
                      `?email=${email}&password=${password}`,
                    {
                      method: 'get',
                      headers: {
                        'X-CSRF-Token': authenticityToken,
                      },
                    },
                  );
                }}
              >
                Sign up
              </Button>
              {omniauthProviders.map((provider) => {
                return (
                  <a
                    key={provider.title}
                    className="Polaris-Button"
                    href={provider.link}
                    data-polaris-unstyled="true"
                    data-method="post"
                  >
                    <span className="Polaris-Button__Content">
                      <span className="Polaris-Button__Text">
                        {provider.title}
                      </span>
                    </span>
                  </a>
                );
              })}
            </FormLayout>
          </Form>
        </Card>
      </Page>
    </AppProvider>
  );
};

export default Login;
