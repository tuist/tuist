import React, { useCallback, useContext, useState } from 'react';
import {
  Page,
  FormLayout,
  TextField,
  Card,
  Button,
  Select,
} from '@shopify/polaris';
import RemoteCachePageStore from './RemoteCachePageStore';
import { observer } from 'mobx-react-lite';
import { useApolloClient } from '@apollo/client';
import { HomeStoreContext } from '@/stores/HomeStore';
import { runInAction } from 'mobx';

const RemoteCachePage = observer(() => {
  const client = useApolloClient();
  const [remoteCachePageStore] = useState(
    () => new RemoteCachePageStore(client),
  );
  const { projectStore } = useContext(HomeStoreContext);

  const handleSelectChange = useCallback(
    (newValue) => {
      runInAction(() => {
        remoteCachePageStore.selectedOption = newValue;
      });
    },
    [remoteCachePageStore],
  );

  const handleBucketNameChange = useCallback((newValue) => {
    runInAction(() => {
      remoteCachePageStore.bucketName = newValue;
    });
  }, []);

  const handleAccessKeyIdChange = useCallback((newValue) => {
    runInAction(() => {
      remoteCachePageStore.accessKeyId = newValue;
    });
  }, []);

  const handleSecretAccessKeyChange = useCallback((newValue) => {
    runInAction(() => {
      remoteCachePageStore.secretAccessKey = newValue;
    });
  }, []);

  const handleApplyChangesClicked = useCallback(() => {
    if (
      projectStore.project === undefined ||
      projectStore.project === null
    ) {
      return;
    }
    remoteCachePageStore.applyChangesButtonClicked(
      projectStore.project.account.id,
    );
  }, [remoteCachePageStore, projectStore]);

  return (
    <Page title="Remote Cache">
      <Card title="S3 Bucket setup" sectioned>
        <FormLayout>
          <Select
            label="S3 Bucket"
            options={remoteCachePageStore.bucketOptions}
            onChange={handleSelectChange}
            value={remoteCachePageStore.selectedOption}
          />
          <TextField
            type="text"
            label="Bucket name"
            value={remoteCachePageStore.bucketName}
            onChange={handleBucketNameChange}
          />
          <TextField
            type="text"
            label="Access key ID"
            value={remoteCachePageStore.accessKeyId}
            onChange={handleAccessKeyIdChange}
          />
          <TextField
            type="password"
            label="Secret access key"
            value={remoteCachePageStore.secretAccessKey}
            onChange={handleSecretAccessKeyChange}
          />
          <Button
            primary
            disabled={
              remoteCachePageStore.isApplyChangesButtonDisabled
            }
            onClick={handleApplyChangesClicked}
          >
            Create bucket
          </Button>
        </FormLayout>
      </Card>
    </Page>
  );
});

export default RemoteCachePage;
