export interface Triple {
  subject: string;
  predicate: string;
  object: string;
  graph: string;
  timestamp: number;
}

export interface VectorEntry {
  text: string;
  vec: number[];
}
