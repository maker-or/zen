import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://zen.pipper.dev",
  // download.html rather than download/index.html; vercel.json serves it as /download.
  build: { format: "file" },
});
