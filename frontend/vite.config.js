import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      // Proxy API and static audio file requests to the FastAPI backend
      '/api': 'http://localhost:8000',
      '/outputs': 'http://localhost:8000',
      '/recordings': 'http://localhost:8000',
      '/project-files': 'http://localhost:8000',
    },
  },
})
