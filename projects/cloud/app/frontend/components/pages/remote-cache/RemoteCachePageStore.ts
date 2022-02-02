import { CreateS3BucketDocument } from '../../../graphql/types';
import { ApolloClient } from '@apollo/client';
import { SelectOption } from '@shopify/polaris';
import { makeAutoObservable } from 'mobx';

class RemoteCachePageStore {
  bucketName = '';
  accessKeyId = '';
  secretAccessKey = '';
  bucketOptions: SelectOption[] = [
    {
      label: 'Create new bucket',
      value: 'new',
    },
  ];
  selectedOption = 'new';

  client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  get isApplyChangesButtonDisabled() {
    return (
      this.bucketName.length === 0 ||
      this.accessKeyId.length === 0 ||
      this.secretAccessKey.length === 0
    );
  }

  get isCreatingBucket() {
    return true;
  }

  async applyChangesButtonClicked(accountId: string) {
    if (this.isCreatingBucket) {
      await this.client.mutate({
        mutation: CreateS3BucketDocument,
        variables: {
          input: {
            name: this.bucketName,
            accessKeyId: this.accessKeyId,
            secretAccessKey: this.secretAccessKey,
            accountId,
          },
        },
      });
    }
  }
}

export default RemoteCachePageStore;
