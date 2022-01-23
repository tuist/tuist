import { makeAutoObservable } from 'mobx';

class RemoteCachePageStore {
  bucketName = '';
  accessKeyID = '';
  secretAccessKey = '';

  constructor() {
    makeAutoObservable(this);
  }

  applyChangesButtonClicked() {
    // TODO: Apply changes
  }
}

export default RemoteCachePageStore;
