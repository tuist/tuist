import ProjectStore from '@/stores/ProjectStore';
import RemoteCachePageStore from '../RemoteCachePageStore';
import { useCallback } from 'react';
import { runInAction } from 'mobx';
import {
  Button,
  FooterHelp,
  FormLayout,
  Link,
  Stack,
  TextField,
  Text,
} from '@shopify/polaris';
import React from 'react';
import { observer } from 'mobx-react-lite';

interface EditBucketProps {
  remoteCachePageStore: RemoteCachePageStore;
  projectStore: ProjectStore;
}

export const EditBucketForm = observer(
  ({ remoteCachePageStore, projectStore }: EditBucketProps) => {
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

    return (
      <FormLayout>
        <TextField
          type="text"
          label="Bucket name"
          value={remoteCachePageStore.bucketName}
          onChange={handleBucketNameChange}
          autoComplete="off"
        />
        <TextField
          type="text"
          label="Region"
          value={remoteCachePageStore.region}
          onChange={handleRegionChange}
          autoComplete="off"
        />
        <TextField
          type="text"
          label="Access key ID"
          value={remoteCachePageStore.accessKeyId}
          onChange={handleAccessKeyIdChange}
          autoComplete="off"
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
            autoComplete="password"
          />
          {remoteCachePageStore.isCreatingBucket === false && (
            <Button onClick={handleRemoveSecretAccessKey}>
              Remove access key
            </Button>
          )}
        </Stack>
        <Button
          primary
          loading={remoteCachePageStore.isApplyChangesButtonLoading}
          disabled={remoteCachePageStore.isApplyChangesButtonDisabled}
          onClick={handleApplyChangesClicked}
        >
          Edit bucket
        </Button>
        <FooterHelp>
          Learn more about getting{' '}
          <Link
            external={true}
            url="https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html"
          >
            access key to your bucket
          </Link>
        </FooterHelp>
      </FormLayout>
    );
  },
);
