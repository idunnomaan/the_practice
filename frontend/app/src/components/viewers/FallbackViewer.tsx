import type { ViewerProps } from "./ViewerProps";

export default function FallbackViewer({ onDownload }: ViewerProps) {
  return (
    <div style={{ padding: 32, textAlign: "center", color: "var(--tx2)" }}>
      <p style={{ marginBottom: 16 }}>
        This file type can&apos;t be previewed in-app yet — please download to open.
      </p>
      <button className="btn btn-primary" onClick={onDownload}>Download</button>
    </div>
  );
}
