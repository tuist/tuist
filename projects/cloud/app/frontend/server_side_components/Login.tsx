import React, { useState } from 'react';
import {
  Page,
  Card,
  FormLayout,
  TextField,
  Checkbox,
  Stack,
  Button,
  Banner,
} from '@shopify/polaris';
import TuistCloudAppProvider from '../components/TuistCloudAppProvider';
import LinkButton from './LinkButton';

interface LoginProps {
  omniauthProviders: [{ title: string; link: string }];
  authenticityToken: string;
  signUpURL: string;
  notice?: string | null;
  alert?: string | null;
}

const Login = ({
  omniauthProviders,
  authenticityToken,
  signUpURL,
  notice,
  alert,
}: LoginProps) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [rememberMe, setRememberMe] = useState(false);
  const [isSignUpButtonLoading, setIsSignUpButtonLoading] =
    useState(false);
  const [isConfirmationSentVisible, setIsConfirmationSentVisible] =
    useState(false);
  const [isNoticeBannerHidden, setIsNoticeBannerHidden] =
    useState(false);
  const [isAlertBannerHidden, setIsAlertBannerHidden] =
    useState(false);
  return (
    <TuistCloudAppProvider>
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
                  setIsConfirmationSentVisible(false);
                }}
              />
              <TextField
                type="password"
                label="Password"
                name="user[password]"
                value={password}
                onChange={(newValue) => {
                  setPassword(newValue);
                  setIsConfirmationSentVisible(false);
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
                <Button
                  loading={isSignUpButtonLoading}
                  disabled={isConfirmationSentVisible}
                  onClick={() => {
                    setIsSignUpButtonLoading(true);
                    fetch(
                      signUpURL +
                        `?email=${email}&password=${password}`,
                      {
                        method: 'get',
                        headers: {
                          'X-CSRF-Token': authenticityToken,
                        },
                      },
                    ).then(() => {
                      setIsSignUpButtonLoading(false);
                      setIsConfirmationSentVisible(true);
                    });
                  }}
                >
                  {isConfirmationSentVisible
                    ? 'Check your email for confirmation link'
                    : 'Sign up'}
                </Button>
                <LinkButton href="/users/confirmation/new">
                  Didn't receive confirmation instructions?
                </LinkButton>
              </Stack>
            </FormLayout>
          </Card.Section>
          <Card.Section title="Social login">
            <Stack vertical={false}>
              {omniauthProviders.map((provider) => {
                // TODO: Fix gitlab
                if (provider.title === 'GitLab') {
                  return null;
                }
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
          <Card.Section>
            {alert && !isAlertBannerHidden && (
              <Banner
                status="warning"
                title={alert}
                onDismiss={() => {
                  setIsAlertBannerHidden(true);
                }}
              />
            )}
            {notice && !isNoticeBannerHidden && (
              <Banner
                title={notice}
                onDismiss={() => {
                  setIsNoticeBannerHidden(true);
                }}
              />
            )}
          </Card.Section>
        </Card>
      </Page>
    </TuistCloudAppProvider>
  );
};

export default Login;
