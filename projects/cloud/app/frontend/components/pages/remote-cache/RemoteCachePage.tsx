import React, { useState } from 'react';
import {
  Page,
  FormLayout,
  TextField,
  Card,
  Button,
} from '@shopify/polaris';
import RemoteCachePageStore from './RemoteCachePageStore';
import { observer } from 'mobx-react-lite';

const RemoteCachePage = observer(() => {
  const [remoteCachePageStore] = useState(
    () => new RemoteCachePageStore(),
  );
  return (
    <Page title="Remote Cache">
      <Card title="S3 Bucket setup" sectioned>
        {/* TODO: Do not let non-admins edit this */}
        <FormLayout>
          {/* In the future, we want to allow more providers like Google cloud here */}
          <TextField
            type="text"
            label="Bucket name"
            value={remoteCachePageStore.bucketName}
            onChange={(newValue) => {
              remoteCachePageStore.bucketName = newValue;
            }}
          />
          <TextField
            type="text"
            label="Access key ID"
            value={remoteCachePageStore.accessKeyID}
            onChange={(newValue) => {
              remoteCachePageStore.accessKeyID = newValue;
            }}
          />
          <TextField
            type="password"
            label="Secret acess key"
            value={remoteCachePageStore.secretAccessKey}
            onChange={(newValue) => {
              remoteCachePageStore.secretAccessKey = newValue;
            }}
          />
          <Button
            primary
            onClick={remoteCachePageStore.applyChangesButtonClicked}
          >
            Apply changes
          </Button>
        </FormLayout>
      </Card>
    </Page>
  );
});

export default RemoteCachePage;
