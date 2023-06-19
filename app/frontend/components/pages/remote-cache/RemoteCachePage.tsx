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
  FooterHelp,
  Link,
  Text,
  Banner,
  Modal,
  ContextualSaveBar,
} from '@shopify/polaris';
import RemoteCachePageStore from './RemoteCachePageStore';
import { observer } from 'mobx-react-lite';
import { useApolloClient } from '@apollo/client';
import { HomeStoreContext } from '@/stores/HomeStore';
import { runInAction } from 'mobx';
import { CreateBucketModal, EditBucketForm } from './components';

export const RemoteCachePage = observer(() => {
  const client = useApolloClient();
  const { projectStore } = useContext(HomeStoreContext);
  const [remoteCachePageStore] = useState(
    () => new RemoteCachePageStore(client, projectStore),
  );

  useEffect(() => {
    remoteCachePageStore.load();
  }, [projectStore.project]);

  const clearCacheError =
    remoteCachePageStore.remoteCacheStorageCleanError ? (
      <Banner
        status="critical"
        onDismiss={() => {
          runInAction(() => {
            remoteCachePageStore.remoteCacheStorageCleanError = null;
          });
        }}
      >
        {remoteCachePageStore.remoteCacheStorageCleanError}
      </Banner>
    ) : null;

  const handleSelectChange = useCallback(
    (newValue) => {
      remoteCachePageStore.handleSelectOption(newValue);
    },
    [remoteCachePageStore],
  );

  const bucket = remoteCachePageStore.isDefaultBucket ? (
    <Text variant="bodyMd" color="subdued" as="p">
      Default bucket created by Tuist Cloud. You can configure your
      own if you want to own the data.
    </Text>
  ) : (
    <EditBucketForm
      remoteCachePageStore={remoteCachePageStore}
      projectStore={projectStore}
    />
  );

  return (
    <Page title="Remote Cache">
      <CreateBucketModal
        onClose={() => {
          runInAction(() => {
            remoteCachePageStore.isCreatingBucket = false;
          });
        }}
        onCreateBucket={(bucket) => {
          remoteCachePageStore.bucketCreated(bucket);
        }}
        open={remoteCachePageStore.isCreatingBucket}
      />
      <Card
        title="S3 Bucket"
        actions={[
          {
            content: 'Create new bucket',
            onAction: () => {
              runInAction(() => {
                remoteCachePageStore.isCreatingBucket = true;
              });
            },
          },
        ]}
      >
        <Card.Section>
          <Stack vertical>
            <Select
              label="Current"
              options={remoteCachePageStore.bucketOptions}
              onChange={handleSelectChange}
              value={remoteCachePageStore.selectedOption}
            />
            {bucket}
          </Stack>
        </Card.Section>
        <Card.Section title="Clear cache">
          <Stack spacing="tight" vertical>
            <Text variant="bodyMd" color="subdued" as="p">
              This will remove all the cached objects in your bucket.
              Any stored cached framework will have to rebuilt and
              uploaded again.
            </Text>
            <Button
              onClick={() => {
                remoteCachePageStore.clearCache();
              }}
              destructive
              plain
              loading={
                remoteCachePageStore.isRemoteCacheStorageCleanLoading
              }
            >
              Clear the project's cache
            </Button>
            {clearCacheError}
          </Stack>
        </Card.Section>
      </Card>
      <Card title="CI cloud token" sectioned>
        <Button
          loading={remoteCachePageStore.isCopyProjectButtonLoading}
          onClick={() => {
            remoteCachePageStore.copyProjectToken();
          }}
        >
          Copy CI cloud token
        </Button>
        <FooterHelp>
          Save this token on your CI to the{' '}
          <b>TUIST_CONFIG_CLOUD_TOKEN</b> variable
        </FooterHelp>
      </Card>
    </Page>
  );
});
