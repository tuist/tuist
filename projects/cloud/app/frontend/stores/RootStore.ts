import { makeAutoObservable, autorun, runInAction, reaction } from "mobx"
import UsersStore from "./UsersStore";

export default class RootStore {
  usersStore: UsersStore;

  constructor() {
    makeAutoObservable(this);
    this.usersStore = new UsersStore();
  }

  async load() {
    this.usersStore.load();
  }
}
