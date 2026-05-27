import type { ViewerProps } from "./ViewerProps";

export default function VideoPlayer({ url }: ViewerProps) {
  return (
    <div style={{ padding: 8 }}>
      {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
      <video
        controls
        src={url}
        style={{ width: "100%", maxHeight: "70vh", background: "#000" }}
      />
    </div>
  );
}
