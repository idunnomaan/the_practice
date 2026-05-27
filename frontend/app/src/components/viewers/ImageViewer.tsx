import { useState } from "react";
import type { ViewerProps } from "./ViewerProps";

export default function ImageViewer({ url, filename }: ViewerProps) {
  const [zoomed, setZoomed] = useState(false);
  return (
    <div style={{ textAlign: "center", padding: 16, overflow: "auto", maxHeight: "70vh" }}>
      <img
        src={url}
        alt={filename}
        onClick={() => setZoomed(z => !z)}
        style={{
          maxWidth: zoomed ? "none" : "100%",
          maxHeight: zoomed ? "none" : "65vh",
          cursor: "zoom-in",
          borderRadius: 4,
        }}
        title={zoomed ? "Click to fit" : "Click to zoom to 100%"}
      />
    </div>
  );
}
