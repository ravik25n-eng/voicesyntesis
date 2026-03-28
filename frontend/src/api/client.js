import axios from 'axios'

const api = axios.create({
  baseURL: '/api',
  timeout: 300_000, // 5 min — model inference can be slow on first run
})

// ── Project API ──────────────────────────────────────────────────────────────

export async function createProject(name) {
  const { data } = await api.post('/projects', { name })
  return data  // { project_id, name, created_at }
}

export async function listProjects() {
  const { data } = await api.get('/projects')
  return data  // [{ project_id, name, created_at, has_recording, has_output, recording_url, output_url }]
}

export async function deleteProject(projectId) {
  const { data } = await api.delete(`/projects/${encodeURIComponent(projectId)}`)
  return data
}

// ── Audio + pipeline API ─────────────────────────────────────────────────────

export async function uploadAudio(projectId, audioBlob) {
  const formData = new FormData()
  const ext = audioBlob.type?.includes('wav') ? 'wav'
    : audioBlob.type?.includes('mp3') || audioBlob.type?.includes('mpeg') ? 'mp3'
    : audioBlob.type?.includes('flac') ? 'flac'
    : audioBlob.type?.includes('ogg') ? 'ogg'
    : 'webm'
  formData.append('audio', audioBlob, `recording.${ext}`)
  const { data } = await api.post(`/upload-audio?project_id=${encodeURIComponent(projectId)}`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  })
  return data
}

export async function transcribeAudio(fileId) {
  const { data } = await api.post('/transcribe', { file_id: fileId })
  return data
}

export async function correctTranscript(rawTranscript, model = 'mistral:latest') {
  const { data } = await api.post('/correct-transcript', {
    raw_transcript: rawTranscript,
    model,
  })
  return data
}

export async function synthesizeVoice(fileId, genText, style = 'standard') {
  const { data } = await api.post('/synthesize', {
    file_id: fileId,
    gen_text: genText,
    style,
  })
  return data  // { file_id, status: "queued" }
}

export async function getStylePresets() {
  const { data } = await api.get('/style-presets')
  return data
}

export async function getSynthesisStatus(fileId) {
  const { data } = await api.get(`/synthesis-status/${fileId}`)
  return data
}

export async function getSubtitles(fileId) {
  const { data } = await api.get(`/subtitle/${fileId}`)
  return data
}

export async function checkHealth() {
  const { data } = await api.get('/health')
  return data
}
