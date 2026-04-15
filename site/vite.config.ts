import { defineConfig } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import path from "node:path";

export default defineConfig({
  plugins: [
    tanstackStart({
      spa: { enabled: true },
    }),
    viteReact(),
  ],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
      "@pi": path.resolve(__dirname, "../pi"),
    },
  },
  server: {
    host: "0.0.0.0",
    port: 5173,
  },
  build: {
    sourcemap: true,
  },
});
