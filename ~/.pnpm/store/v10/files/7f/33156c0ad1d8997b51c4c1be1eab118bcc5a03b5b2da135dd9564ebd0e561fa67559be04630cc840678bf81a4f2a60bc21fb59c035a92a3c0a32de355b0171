/**
 * Check if a node is a *embedded content*.
 *
 * @param value
 *   Thing to check (typically `Node`).
 * @returns
 *   Whether `value` is an element considered embedded content.
 *
 *   The elements `audio`, `canvas`, `embed`, `iframe`, `img`, `math`,
 *   `object`, `picture`, `svg`, and `video` are embedded content.
 */
export const embedded: (element: unknown, index?: number | null | undefined, parent?: import("hast").Parents | null | undefined, context?: unknown) => element is import("hast").Element & {
    tagName: 'audio' | 'canvas' | 'embed' | 'iframe' | 'img' | 'math' | 'object' | 'picture' | 'svg' | 'video';
};
