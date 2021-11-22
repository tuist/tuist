import { makeAutoObservable, autorun, runInAction, reaction } from "mobx"

export default class UsersStore {
  constructor() {
    makeAutoObservable(this);
    this.load()
  }

  load() {

  }
}
