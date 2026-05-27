import type { ComponentType } from "react";
import type { ViewerProps } from "../components/viewers/ViewerProps";
import PdfViewer from "../components/viewers/PdfViewer";
import ImageViewer from "../components/viewers/ImageViewer";
import AudioPlayer from "../components/viewers/AudioPlayer";
import VideoPlayer from "../components/viewers/VideoPlayer";
import TextViewer from "../components/viewers/TextViewer";
import CsvViewer from "../components/viewers/CsvViewer";
import DocxViewer from "../components/viewers/DocxViewer";
import FallbackViewer from "../components/viewers/FallbackViewer";

export function chooseViewer(contentType: string): ComponentType<ViewerProps> {
  const t = contentType.toLowerCase().split(";")[0].trim();

  if (t === "application/pdf") return PdfViewer;
  if (t.startsWith("image/")) return ImageViewer;
  if (t.startsWith("audio/")) return AudioPlayer;
  if (t.startsWith("video/")) return VideoPlayer;
  if (t === "text/plain" || t === "text/markdown") return TextViewer;
  if (t === "text/csv") return CsvViewer;
  if (t === "application/vnd.openxmlformats-officedocument.wordprocessingml.document") return DocxViewer;

  return FallbackViewer;
}
