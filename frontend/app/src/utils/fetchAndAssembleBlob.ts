export interface FetchAndAssembleBlobArgs {
  prepare: () => Promise<{ chunkCount: bigint; contentType: string; filename: string }>;
  getChunk: (i: bigint) => Promise<Uint8Array | null>;
  onProgress?: (loaded: number, total: number) => void;
}

export interface AssembledBlob {
  blob: Blob;
  url: string;
  filename: string;
  contentType: string;
}

const BATCH_SIZE = 8;

export async function fetchAndAssembleBlob(args: FetchAndAssembleBlobArgs): Promise<AssembledBlob> {
  const { chunkCount, contentType, filename } = await args.prepare();
  const total = Number(chunkCount);
  const parts: Uint8Array[] = [];
  for (let i = 0; i < total; i += BATCH_SIZE) {
    const end = Math.min(i + BATCH_SIZE, total);
    const batchIndices = Array.from({ length: end - i }, (_, j) => i + j);
    const batchChunks = await Promise.all(batchIndices.map(idx => args.getChunk(BigInt(idx))));
    for (const chunk of batchChunks) {
      if (chunk) parts.push(chunk);
    }
    args.onProgress?.(end, total);
  }
  const blob = new Blob(parts, { type: contentType });
  const url = URL.createObjectURL(blob);
  return { blob, url, filename, contentType };
}
