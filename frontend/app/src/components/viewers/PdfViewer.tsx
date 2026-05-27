import type { ViewerProps } from "./ViewerProps";

export default function PdfViewer({ url }: ViewerProps) {
  return (
    <iframe
      src={url}
      style={{ width: "100%", height: "70vh", border: "none", background: "#fff" }}
      title="PDF preview"
    />
  );
}
