import { defineConfig } from "vite";

export default defineConfig({
  server: {
    allowedHosts: [".ts.net"],
  },
  preview: {
    allowedHosts: [".ts.net"],
  },
});
