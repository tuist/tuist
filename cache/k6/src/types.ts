export interface SizeBucket {
  name: string;
  bytes: number;
  weight: number;
}

export interface XcodeSeeded {
  casIds: string[];
  kvCasIds: string[];
}

export interface ModuleSeeded {
  refs: Array<{ hash: string; name: string }>;
}

export interface GradleSeeded {
  keys: string[];
}

export interface SetupData {
  token: string;
  xcode: Record<string, XcodeSeeded>;
  module: Record<string, ModuleSeeded>;
  gradle: Record<string, GradleSeeded>;
  kvDirect: string[];
}
