export interface ViewerProps {
  url: string;
  blob: Blob;
  filename: string;
  contentType: string;
  sizeBytes: bigint;
  onDownload: () => void;
}
