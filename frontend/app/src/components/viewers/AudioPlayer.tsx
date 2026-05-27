import type { ViewerProps } from "./ViewerProps";

export default function AudioPlayer({ url }: ViewerProps) {
  return (
    <div style={{ padding: 24, display: "flex", justifyContent: "center" }}>
      {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
      <audio controls src={url} style={{ width: "100%", maxWidth: 480 }} />
    </div>
  );
}
