import { useApolloClient } from '@apollo/client';
import {
  Button,
  FormLayout,
  Modal,
  ModalProps,
  Page,
  Stack,
  TextField,
} from '@shopify/polaris';
import { observer } from 'mobx-react-lite';
import React, { useContext, useState } from 'react';
import { CreateBucketStore } from './CreateBucketStore';
import { runInAction } from 'mobx';
import { S3Bucket } from '@/models';
import { HomeStoreContext } from '@/stores/HomeStore';

interface Props extends Pick<ModalProps, 'onClose' | 'open'> {
  onCreateBucket: (bucket: S3Bucket) => void;
}

export const CreateBucketModal = observer(
  ({ onClose, open, onCreateBucket }: Props) => {
    const client = useApolloClient();
    const { projectStore } = useContext(HomeStoreContext);
    const [createBucketStore] = useState(
      () => new CreateBucketStore(client, projectStore),
    );

    return (
      <Modal title="Create new bucket" onClose={onClose} open={open}>
        <Page>
          <FormLayout>
            <TextField
              type="text"
              label="Bucket name"
              value={createBucketStore.bucketName}
              onChange={(bucketName) => {
                runInAction(() => {
                  createBucketStore.bucketName = bucketName;
                });
              }}
              autoComplete="off"
            />
            <TextField
              type="text"
              label="Region"
              value={createBucketStore.region}
              onChange={(region) => {
                runInAction(() => {
                  createBucketStore.region = region;
                });
              }}
              autoComplete="off"
            />
            <TextField
              type="text"
              label="Access key ID"
              value={createBucketStore.accessKeyId}
              onChange={(accessKeyId) => {
                runInAction(() => {
                  createBucketStore.accessKeyId = accessKeyId;
                });
              }}
              autoComplete="off"
            />
            <Stack alignment="trailing" distribution="fill">
              <TextField
                type="password"
                label="Secret access key"
                value={createBucketStore.secretAccessKey}
                onChange={(secretAccessKey) => {
                  runInAction(() => {
                    createBucketStore.secretAccessKey =
                      secretAccessKey;
                  });
                }}
                autoComplete="password"
              />
            </Stack>
            <Button
              primary
              loading={createBucketStore.saving}
              disabled={createBucketStore.isCreateButtonDisabled}
              onClick={async () => {
                const bucket = await createBucketStore.createBucket();
                if (bucket) {
                  onCreateBucket(bucket);
                }
              }}
            >
              Create bucket
            </Button>
          </FormLayout>
        </Page>
      </Modal>
    );
  },
);
