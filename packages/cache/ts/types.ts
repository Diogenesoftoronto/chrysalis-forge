export interface CacheEntry {
  value: string;
  createdAt: number;
  ttl: number;
  tags: string[];
}

export interface CacheStats {
  total: number;
  valid: number;
  expired: number;
  tags: Record<string, number>;
}
