import React from 'react';
import {
  Page,
  Card,
  FormLayout,
  TextField,
  Button,
} from '@shopify/polaris';
import { Link, useNavigate } from 'react-router-dom';

const Login = () => {
  const navigate = useNavigate();

  return (
    <Page title="Remote Cache">
      <Card title="S3 Bucket setup" sectioned>
        <FormLayout>
          <TextField
            type="text"
            label="Bucket name"
            value={''}
            onChange={() => {}}
            // value={remoteCachePageStore.bucketName}
            // onChange={handleBucketNameChange}
          />
          <Button
            onClick={() => {
              fetch('/users/auth/github', { method: 'POST' });
            }}
          >
            Github
          </Button>
        </FormLayout>
      </Card>
    </Page>
  );
};

export default Login;
