import React, { useState } from 'react';
import { Page, Card, FormLayout, TextField } from '@shopify/polaris';

import TuistCloudAppProvider from '../components/TuistCloudAppProvider';
import LinkButton from './LinkButton';

interface ResendConfirmationProps {
  authenticityToken: string;
}

const ResendConfirmation = ({
  authenticityToken,
}: ResendConfirmationProps) => {
  const [email, setEmail] = useState('');

  return (
    <TuistCloudAppProvider>
      <Page title="Resend confirmation instructions">
        <Card>
          <Card.Section>
            <FormLayout>
              <TextField
                type="email"
                label="Email"
                value={email}
                onChange={(newValue) => {
                  setEmail(newValue);
                }}
              />
              <LinkButton
                href={`/users/confirmation?authenticity_token=${authenticityToken}&user[email]=${email}`}
                method="post"
              >
                Resend
              </LinkButton>
            </FormLayout>
          </Card.Section>
        </Card>
      </Page>
    </TuistCloudAppProvider>
  );
};

export default ResendConfirmation;
