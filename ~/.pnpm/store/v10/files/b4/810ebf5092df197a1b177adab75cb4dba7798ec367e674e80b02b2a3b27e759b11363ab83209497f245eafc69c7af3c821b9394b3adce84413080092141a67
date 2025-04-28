import { PanelGroupStorage } from '../SplitterGroup';
import { PanelData } from '../SplitterPanel';
export declare function initializeDefaultStorage(storageObject: PanelGroupStorage): void;
export type PanelConfigurationState = {
    expandToSizes: {
        [panelId: string]: number;
    };
    layout: number[];
};
export type SerializedPanelGroupState = {
    [panelIds: string]: PanelConfigurationState;
};
export declare function loadPanelGroupState(autoSaveId: string, panels: PanelData[], storage: PanelGroupStorage): PanelConfigurationState | null;
export declare function savePanelGroupState(autoSaveId: string, panels: PanelData[], panelSizesBeforeCollapse: Map<string, number>, sizes: number[], storage: PanelGroupStorage): void;
