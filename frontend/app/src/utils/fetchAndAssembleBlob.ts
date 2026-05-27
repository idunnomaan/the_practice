export interface FetchAndAssembleBlobArgs {
  prepare: () => Promise<{ chunkCount: bigint; contentType: string; filename: string }>;
  getChunk: (i: bigint) => Promise<Uint8Array | null>;
}

export interface AssembledBlob {
  blob: Blob;
  url: string;
  filename: string;
  contentType: string;
}

export async function fetchAndAssembleBlob(args: FetchAndAssembleBlobArgs): Promise<AssembledBlob> {
  const { chunkCount, contentType, filename } = await args.prepare();
  const parts: Uint8Array[] = [];
  for (let i = 0n; i < chunkCount; i++) {
    const chunk = await args.getChunk(i);
    if (chunk) parts.push(chunk);
  }
  const blob = new Blob(parts, { type: contentType });
  const url = URL.createObjectURL(blob);
  return { blob, url, filename, contentType };
}
