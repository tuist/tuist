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
} from '@shopify/polaris';
import RemoteCachePageStore from './RemoteCachePageStore';
import { observer } from 'mobx-react-lite';
import { useApolloClient } from '@apollo/client';
import { HomeStoreContext } from '@/stores/HomeStore';
import { runInAction } from 'mobx';

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

  const handleRegionChange = useCallback(
    (newValue) => {
      runInAction(() => {
        remoteCachePageStore.region = newValue;
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

  return (
    <Page title="Remote Cache">
      <Card title="S3 Bucket">
        <Card.Section>
          <FormLayout>
            <Select
              label="Current"
              options={remoteCachePageStore.bucketOptions}
              onChange={handleSelectChange}
              value={remoteCachePageStore.selectedOption}
            />
            {!remoteCachePageStore.isDefaultBucket && (
              <TextField
                type="text"
                label="Bucket name"
                value={remoteCachePageStore.bucketName}
                onChange={handleBucketNameChange}
                autoComplete="off"
              />
            )}
            {!remoteCachePageStore.isDefaultBucket && (
              <TextField
                type="text"
                label="Region"
                value={remoteCachePageStore.region}
                onChange={handleRegionChange}
                autoComplete="off"
              />
            )}
            {!remoteCachePageStore.isDefaultBucket && (
              <TextField
                type="text"
                label="Access key ID"
                value={remoteCachePageStore.accessKeyId}
                onChange={handleAccessKeyIdChange}
                autoComplete="off"
              />
            )}
            {!remoteCachePageStore.isDefaultBucket && (
              <Stack alignment="trailing" distribution="fill">
                <TextField
                  disabled={
                    remoteCachePageStore.isSecretAccessKeyTextFieldDisabled
                  }
                  type="password"
                  label="Secret access key"
                  value={remoteCachePageStore.secretAccessKey}
                  onChange={handleSecretAccessKeyChange}
                  autoComplete="password"
                />
                {remoteCachePageStore.isCreatingBucket === false && (
                  <Button onClick={handleRemoveSecretAccessKey}>
                    Remove access key
                  </Button>
                )}
              </Stack>
            )}
            {!remoteCachePageStore.isDefaultBucket && (
              <Button
                primary
                loading={
                  remoteCachePageStore.isApplyChangesButtonLoading
                }
                disabled={
                  remoteCachePageStore.isApplyChangesButtonDisabled
                }
                onClick={handleApplyChangesClicked}
              >
                {remoteCachePageStore.isCreatingBucket
                  ? 'Create bucket'
                  : 'Edit bucket'}
              </Button>
            )}
            {remoteCachePageStore.isDefaultBucket && (
              <Text variant="bodyMd" color="subdued" as="p">
                Default bucket created by Tuist Cloud. You can
                configure your own if you want to own the data.
              </Text>
            )}
            {!remoteCachePageStore.isDefaultBucket && (
              <FooterHelp>
                Learn more about getting{' '}
                <Link
                  external={true}
                  url="https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html"
                >
                  access key to your bucket
                </Link>
              </FooterHelp>
            )}
          </FormLayout>
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

export default RemoteCachePage;
