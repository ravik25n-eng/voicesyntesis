import { useState, useEffect, useRef } from 'react'
import { Wand2, Download, RefreshCw, CheckCircle2, Circle, Loader2, AlertCircle, Captions } from 'lucide-react'
import { synthesizeVoice, getSynthesisStatus, getSubtitles } from '../api/client'

// Pipeline phases shown in order in the UI
const PHASES = [
  { key: 'queued',          label: 'Queued' },
  { key: 'loading_model',   label: 'Load Model' },
  { key: 'preparing_audio', label: 'Prepare Audio' },
  { key: 'synthesizing',    label: 'Synthesise' },
  { key: 'done',            label: 'Complete' },
]

const PHASE_ORDER = PHASES.map((p) => p.key)

function PhaseIcon({ phaseKey, currentStatus }) {
  const currentIdx = PHASE_ORDER.indexOf(currentStatus === 'error' ? 'queued' : currentStatus)
  const thisIdx = PHASE_ORDER.indexOf(phaseKey)

  if (currentStatus === 'error' && thisIdx <= currentIdx) {
    return <AlertCircle size={18} className="text-red-400 shrink-0" />
  }
  if (thisIdx < currentIdx || currentStatus === 'done') {
    return <CheckCircle2 size={18} className="text-pink-400 shrink-0" />
  }
  if (thisIdx === currentIdx) {
    return <Loader2 size={18} className="text-pink-400 shrink-0 animate-spin" />
  }
  return <Circle size={18} className="text-slate-700 shrink-0" />
}

/**
 * Step 3 — Clone voice from reference recording and synthesize final transcript.
 * genText: the user's final edited transcript (what gets synthesised)
 * F5-TTS auto-transcribes its own internal 12s clip for voice alignment.
 */
export default function VoiceSynthesizer({ fileId, genText, style = 'standard', onReset }) {
  const [phase, setPhase] = useState('ready') // ready | running | done | error
  const [jobStatus, setJobStatus] = useState(null)
  const [audioUrl, setAudioUrl] = useState(null)
  const [error, setError] = useState(null)
  const [subtitles, setSubtitles] = useState(null)
  const [subtitleLoading, setSubtitleLoading] = useState(false)
  const [subtitleError, setSubtitleError] = useState(null)
  const pollRef = useRef(null)

  // Clean up polling on unmount
  useEffect(() => () => clearInterval(pollRef.current), [])

  const startPolling = (fileId) => {
    pollRef.current = setInterval(async () => {
      try {
        const status = await getSynthesisStatus(fileId)
        setJobStatus(status)

        if (status.status === 'done') {
          clearInterval(pollRef.current)
          setAudioUrl(status.audio_url)
          setPhase('done')
          // Auto-extract subtitles from the synthesized output
          fetchSubtitles(fileId)
        } else if (status.status === 'error') {
          clearInterval(pollRef.current)
          setError(status.message)
          setPhase('error')
        }
      } catch {
        clearInterval(pollRef.current)
        setError('Lost connection to the backend. Is it still running?')
        setPhase('error')
      }
    }, 2000)
  }

  const handleSynthesize = async () => {
    setPhase('running')
    setJobStatus({ status: 'queued', message: 'Queuing synthesis job…', progress: 0 })
    setError(null)

    try {
      await synthesizeVoice(fileId, genText, style)
      startPolling(fileId)
    } catch (err) {
      setError(err?.response?.data?.detail ?? 'Failed to start synthesis. Is the backend running?')
      setPhase('error')
    }
  }

  const handleReset = () => {
    clearInterval(pollRef.current)
    onReset()
  }

  const fetchSubtitles = async (id) => {
    setSubtitleLoading(true)
    setSubtitleError(null)
    try {
      const result = await getSubtitles(id)
      setSubtitles(result)
    } catch {
      setSubtitleError('Could not extract subtitles. Try after the backend restarts.')
    } finally {
      setSubtitleLoading(false)
    }
  }

  // ── Ready state ──────────────────────────────────────────────────────────

  if (phase === 'ready') {
    return (
      <div className="bg-slate-900 rounded-2xl p-6 border border-slate-800 space-y-6">
        <div>
          <h2 className="text-lg font-semibold text-white mb-1">Voice Synthesis</h2>
          <p className="text-sm text-gray-400">
            F5-TTS will clone your voice from the reference recording and speak the transcript below.
          </p>
        </div>

        <div className="bg-slate-950 rounded-xl border border-slate-800 px-4 py-4 space-y-1">
          <p className="text-xs text-gray-500 font-medium uppercase tracking-wide">Transcript to synthesise</p>
          <p className="text-gray-200 text-sm leading-relaxed whitespace-pre-wrap">{genText}</p>
        </div>

        <button
          onClick={handleSynthesize}
          className="flex items-center gap-2 px-5 py-2.5 bg-pink-600 hover:bg-pink-500 text-white rounded-xl font-medium transition-colors"
        >
          <Wand2 size={17} />
          Clone Voice &amp; Synthesise
        </button>
      </div>
    )
  }

  // ── Running state — live status phases ───────────────────────────────────

  if (phase === 'running') {
    const currentStatus = jobStatus?.status ?? 'queued'
    const currentMessage = jobStatus?.message ?? 'Starting…'
    const progress = jobStatus?.progress ?? 0

    return (
      <div className="bg-slate-900 rounded-2xl p-6 border border-slate-800 space-y-6">
        <div>
          <h2 className="text-lg font-semibold text-white mb-1">Voice Synthesis</h2>
          <p className="text-sm text-gray-400">Processing your voice clone — do not close this tab.</p>
        </div>

        {/* Phase steps */}
        <div className="space-y-2">
          {PHASES.map((p) => {
            const thisIdx = PHASE_ORDER.indexOf(p.key)
            const curIdx = PHASE_ORDER.indexOf(currentStatus === 'error' ? 'queued' : currentStatus)
            const isActive = p.key === currentStatus
            const isDone = thisIdx < curIdx

            return (
              <div
                key={p.key}
                className={[
                  'flex items-start gap-3 px-4 py-3 rounded-xl border transition-all duration-300',
                  isActive && 'border-pink-700 bg-pink-950/30',
                  isDone && 'border-slate-800 bg-slate-800/30',
                  !isActive && !isDone && 'border-transparent',
                ].filter(Boolean).join(' ')}
              >
                <PhaseIcon phaseKey={p.key} currentStatus={currentStatus} />
                <div className="min-w-0">
                  <p className={[
                    'text-sm font-medium',
                    isActive ? 'text-white' : isDone ? 'text-gray-500' : 'text-slate-700',
                  ].join(' ')}>
                    {p.label}
                  </p>
                  {/* Show live message only on the active phase */}
                  {isActive && (
                    <p className="text-xs text-pink-300 mt-0.5 leading-snug">{currentMessage}</p>
                  )}
                </div>
              </div>
            )
          })}
        </div>

        {/* Progress bar */}
        {progress > 0 && (
          <div className="space-y-1">
            <div className="w-full h-1.5 bg-slate-800 rounded-full overflow-hidden">
              <div
                className="h-full bg-pink-500 rounded-full transition-all duration-700"
                style={{ width: `${progress}%` }}
              />
            </div>
            <p className="text-xs text-gray-600 tabular-nums text-right">{progress}%</p>
          </div>
        )}

        {/* First-run hint */}
        {currentStatus === 'loading_model' && (
          <div className="text-xs text-gray-500 bg-slate-800 rounded-xl px-4 py-3 space-y-1 border border-slate-700">
            <p className="font-medium text-gray-400">First-time setup</p>
            <p>The F5-TTS model (~1.5 GB) is downloading from HuggingFace. This only happens once — the model is cached locally for all future runs.</p>
            <p className="mt-1">Monitor in terminal: <code className="text-pink-400">du -sh ~/.cache/huggingface/</code></p>
          </div>
        )}
      </div>
    )
  }

  // ── Error state ──────────────────────────────────────────────────────────

  if (phase === 'error') {
    return (
      <div className="bg-slate-900 rounded-2xl p-6 border border-slate-800 space-y-4">
        <h2 className="text-lg font-semibold text-white">Synthesis Failed</h2>
        <div className="text-sm text-red-400 bg-red-950/30 border border-red-800 rounded-xl px-4 py-3">
          {error}
        </div>
        <button
          onClick={handleSynthesize}
          className="flex items-center gap-2 text-sm text-red-400 hover:text-red-300"
        >
          <RefreshCw size={14} />
          Retry synthesis
        </button>
      </div>
    )
  }

  // ── Done state ───────────────────────────────────────────────────────────

  return (
    <div className="bg-slate-900 rounded-2xl p-6 border border-slate-800 space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-white mb-1">Voice Synthesis Complete</h2>
        <p className="text-sm text-gray-400">Your cloned voice has been synthesised successfully.</p>
      </div>

      <div className="bg-slate-800 rounded-xl p-4 space-y-3">
        <p className="text-sm font-medium text-gray-200">Synthesised Audio</p>
        <audio src={audioUrl} controls className="w-full rounded-lg" />
        <a
          href={audioUrl}
          download="synthesized_voice.wav"
          className="inline-flex items-center gap-1.5 text-sm text-pink-400 hover:text-pink-300 transition-colors"
        >
          <Download size={14} />
          Download WAV
        </a>
      </div>

      <div className="text-xs text-gray-500 bg-slate-800 rounded-xl px-4 py-3 border border-slate-700">
        Compare with your{' '}
        <a
          href={`/project-files/${fileId}/recording.wav`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-pink-400 hover:text-pink-300 underline underline-offset-2"
        >
          original recording
        </a>
        .
      </div>

      {/* ── Subtitle / Verification panel ── */}
      <div className="border border-slate-800 rounded-xl overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 bg-slate-800">
          <div className="flex items-center gap-2 text-sm font-medium text-gray-200">
            <Captions size={16} className="text-pink-400" />
            Subtitle Verification
          </div>
          {!subtitles && !subtitleLoading && (
            <button
              onClick={() => fetchSubtitles(fileId)}
              className="text-xs text-pink-400 hover:text-pink-300 transition-colors"
            >
              Extract subtitles
            </button>
          )}
        </div>

        <div className="px-4 py-3 bg-slate-950 space-y-3">
          {subtitleLoading && (
            <div className="flex items-center gap-2 text-sm text-pink-400 py-2">
              <Loader2 size={14} className="animate-spin shrink-0" />
              Transcribing synthesised audio with Whisper…
            </div>
          )}

          {subtitleError && (
            <p className="text-sm text-red-400">{subtitleError}</p>
          )}

          {subtitles && !subtitleLoading && (
            <div className="space-y-3">
              {/* Comparison */}
              <div className="grid grid-cols-2 gap-3 text-xs">
                <div className="space-y-1">
                  <p className="text-gray-500 uppercase tracking-wide font-medium">Intended transcript</p>
                  <p className="text-gray-300 leading-relaxed">{genText}</p>
                </div>
                <div className="space-y-1">
                  <p className="text-gray-500 uppercase tracking-wide font-medium">
                    What was actually spoken
                    <span className="ml-2 text-gray-600 normal-case tracking-normal">
                      ({subtitles.duration}s · {subtitles.language?.toUpperCase()})
                    </span>
                  </p>
                  <p className="text-gray-300 leading-relaxed">{subtitles.text}</p>
                </div>
              </div>

              {/* Timestamped segments */}
              {subtitles.segments.length > 0 && (
                <div className="space-y-1">
                  <p className="text-xs text-gray-600 font-medium uppercase tracking-wide">Timestamped segments</p>
                  <div className="divide-y divide-slate-800 rounded-lg border border-slate-800 overflow-hidden">
                    {subtitles.segments.map((seg, i) => (
                      <div key={i} className="flex items-start gap-3 px-3 py-2 text-xs">
                        <span className="text-pink-500 font-mono whitespace-nowrap shrink-0 tabular-nums">
                          {seg.start.toFixed(1)}s → {seg.end.toFixed(1)}s
                        </span>
                        <span className="text-gray-300">{seg.text}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {!subtitles && !subtitleLoading && !subtitleError && (
            <p className="text-xs text-gray-600 py-1">
              Click "Extract subtitles" above to verify what was synthesised.
            </p>
          )}
        </div>
      </div>

      <button
        onClick={handleReset}
        className="flex items-center gap-2 px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl font-medium transition-colors"
      >
        <RefreshCw size={17} />
        Start New Session
      </button>
    </div>
  )
}

