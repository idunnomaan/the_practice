import { createContext, useContext } from "react";

export type FileViewerSource =
  | { kind: "document"; id: bigint; versionId: bigint; filename: string; contentType: string; sizeBytes: bigint }
  | { kind: "library"; id: bigint; versionId: bigint; filename: string; contentType: string; sizeBytes: bigint };

export interface FileViewerState {
  open: boolean;
  source: FileViewerSource | null;
}

export interface FileViewerContextValue {
  state: FileViewerState;
  openViewer: (source: FileViewerSource) => void;
  closeViewer: () => void;
}

export const FileViewerContext = createContext<FileViewerContextValue>({
  state: { open: false, source: null },
  openViewer: () => undefined,
  closeViewer: () => undefined,
});

export function useFileViewer() {
  return useContext(FileViewerContext);
}
