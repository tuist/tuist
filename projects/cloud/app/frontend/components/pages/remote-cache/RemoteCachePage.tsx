import React, {
  useCallback,
  useContext,
  useEffect,
  useState,
} from 'react';
import {
  Page,
  FormLayout,
  TextField,
  Card,
  Button,
  Select,
  Stack,
} from '@shopify/polaris';
import RemoteCachePageStore from './RemoteCachePageStore';
import { observer } from 'mobx-react-lite';
import { useApolloClient } from '@apollo/client';
import { HomeStoreContext } from '@/stores/HomeStore';
import { autorun, runInAction } from 'mobx';

const RemoteCachePage = observer(() => {
  const client = useApolloClient();
  const { projectStore } = useContext(HomeStoreContext);
  const [remoteCachePageStore] = useState(
    () => new RemoteCachePageStore(client, projectStore),
  );

  useEffect(() => {
    remoteCachePageStore.load();
  }, [projectStore.project]);

  const handleSelectChange = useCallback(
    (newValue) => {
      remoteCachePageStore.handleSelectOption(newValue);
    },
    [remoteCachePageStore],
  );

  const handleBucketNameChange = useCallback(
    (newValue) => {
      runInAction(() => {
        remoteCachePageStore.bucketName = newValue;
      });
    },
    [remoteCachePageStore],
  );

  const handleAccessKeyIdChange = useCallback(
    (newValue) => {
      runInAction(() => {
        remoteCachePageStore.accessKeyId = newValue;
      });
    },
    [remoteCachePageStore],
  );

  const handleSecretAccessKeyChange = useCallback(
    (newValue) => {
      runInAction(() => {
        remoteCachePageStore.secretAccessKey = newValue;
      });
    },
    [remoteCachePageStore],
  );

  const handleRemoveSecretAccessKey = useCallback(() => {
    remoteCachePageStore.removeAccessKey();
  }, [remoteCachePageStore]);

  const handleApplyChangesClicked = useCallback(() => {
    if (projectStore.project == undefined) {
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
          <Stack alignment="trailing" distribution="fill">
            <TextField
              disabled={
                remoteCachePageStore.isSecretAccessKeyTextFieldDisabled
              }
              type="password"
              label="Secret access key"
              value={remoteCachePageStore.secretAccessKey}
              onChange={handleSecretAccessKeyChange}
            />
            {remoteCachePageStore.isCreatingBucket === false && (
              <Button onClick={handleRemoveSecretAccessKey}>
                Remove access key
              </Button>
            )}
          </Stack>
          <Button
            primary
            disabled={
              remoteCachePageStore.isApplyChangesButtonDisabled
            }
            onClick={handleApplyChangesClicked}
          >
            {remoteCachePageStore.isCreatingBucket
              ? 'Create bucket'
              : 'Edit bucket'}
          </Button>
        </FormLayout>
      </Card>
    </Page>
  );
});

export default RemoteCachePage;
