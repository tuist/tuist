import { makeAutoObservable } from 'mobx';

class RemoteCachePageStore {
  bucketName = '';
  accessKeyID = '';
  secretAccessKey = '';

  constructor() {
    makeAutoObservable(this);
  }

  get isApplyChangesButtonDisabled() {
    return (
      this.bucketName.length === 0 ||
      this.accessKeyID.length === 0 ||
      this.secretAccessKey.length === 0
    );
  }

  get isCreatingBucket() {
    return true;
  }

  applyChangesButtonClicked() {
    // TODO: Apply changes
  }
}

export default RemoteCachePageStore;
