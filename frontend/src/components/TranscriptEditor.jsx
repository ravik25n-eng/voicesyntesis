import { useState, useEffect, useRef } from 'react'
import { Wand2, Play, Pause, ChevronRight, RotateCcw } from 'lucide-react'
import { transcribeAudio, correctTranscript, getStylePresets } from '../api/client'

/**
 * Handles Step 2 of the pipeline:
 *  1. Auto-transcribes the uploaded audio via Whisper
 *  2. Lets the user edit the transcript manually
 *  3. Optionally improves it via Ollama (can be run repeatedly on current text)
 *  4. Finalises — calls onFinalized({ raw, final }) where:
 *       raw   = original Whisper output (used as ref_text by F5-TTS for voice cloning)
 *       final = user's edited/corrected text (what gets synthesised)
 */
export default function TranscriptEditor({ fileId, onFinalized }) {
  // phase: 'transcribing' | 'editing' | 'improving'
  const [phase, setPhase] = useState('transcribing')
  const [transcript, setTranscript] = useState('')          // editable — what gets synthesised
  const [whisperOriginal, setWhisperOriginal] = useState('') // raw Whisper output, stored for undo
  const [isImproved, setIsImproved] = useState(false)       // whether current text is AI-improved
  const [language, setLanguage] = useState('')
  const [error, setError] = useState(null)
  const [isPlaying, setIsPlaying] = useState(false)
  const [selectedStyle, setSelectedStyle] = useState('standard')
  const [stylePresets, setStylePresets] = useState([])
  const audioElRef = useRef(null)

  // Auto-start transcription and load style presets on mount
  useEffect(() => {
    runTranscription()
    getStylePresets().then(setStylePresets).catch(() => {})
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const runTranscription = async () => {
    setPhase('transcribing')
    setError(null)
    try {
      const result = await transcribeAudio(fileId)
      setTranscript(result.text)
      setWhisperOriginal(result.text)
      setIsImproved(false)
      setLanguage(result.language)
      setPhase('editing')
    } catch (err) {
      setError(err?.response?.data?.detail ?? 'Transcription failed. Check the backend logs.')
    }
  }

  const runImprovement = async () => {
    if (!transcript.trim()) return
    setPhase('improving')
    setError(null)
    try {
      const result = await correctTranscript(transcript)
      setTranscript(result.corrected_text)
      setIsImproved(true)
      setPhase('editing')
    } catch (err) {
      const detail = err?.response?.data?.detail ?? err?.message ?? 'AI improvement failed.'
      setError(`${detail} — make sure Ollama is running and the mistral model is pulled (ollama pull mistral).`)
      setPhase('editing')
    }
  }

  const handleRestoreOriginal = () => {
    setTranscript(whisperOriginal)
    setIsImproved(false)
  }

  const handleFinalize = () => {
    // raw = original Whisper output (ref_text for F5-TTS alignment)
    // final = whatever the user has now (edited or AI-improved)
    onFinalized({ raw: whisperOriginal, final: transcript, style: selectedStyle })
  }

  const toggleOriginalPlay = () => {
    const url = `/project-files/${fileId}/recording.wav`
    if (!audioElRef.current) {
      audioElRef.current = new Audio(url)
      audioElRef.current.onended = () => setIsPlaying(false)
    }
    if (isPlaying) {
      audioElRef.current.pause()
      setIsPlaying(false)
    } else {
      audioElRef.current.play()
      setIsPlaying(true)
    }
  }

  // ── Transcribing spinner ─────────────────────────────────────────────────

  if (phase === 'transcribing') {
    return (
      <div className="bg-slate-900 rounded-2xl p-6 border border-slate-800 space-y-6">
        <div>
          <h2 className="text-lg font-semibold text-white mb-1">Transcribing Audio</h2>
          <p className="text-sm text-gray-400">
            Whisper large-v3 is analysing your recording. This may take 10–30 seconds.
          </p>
        </div>

        <div className="flex items-center gap-3 text-pink-400 py-4">
          <span className="w-5 h-5 rounded-full border-2 border-pink-400 border-t-transparent animate-spin shrink-0" />
          <span className="text-sm">Running Whisper large-v3 on CPU (int8)…</span>
        </div>

        {error && (
          <div className="text-sm text-red-400 bg-red-950/30 border border-red-800 rounded-xl px-4 py-3 space-y-2">
            <p>{error}</p>
            <button
              onClick={runTranscription}
              className="flex items-center gap-1.5 text-red-400 hover:text-red-300 underline underline-offset-2"
            >
              <RotateCcw size={13} /> Retry
            </button>
          </div>
        )}
      </div>
    )
  }

  // ── Editing UI ───────────────────────────────────────────────────────────

  const isImproving = phase === 'improving'

  return (
    <div className="bg-slate-900 rounded-2xl p-6 border border-slate-800 space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-lg font-semibold text-white mb-1">Review &amp; Refine Transcript</h2>
          <p className="text-sm text-gray-400">
            Edit freely, or click <span className="text-pink-400 font-medium">Improve with AI</span> to let Ollama enhance the current text.
          </p>
        </div>

        {/* Listen to original */}
        <button
          onClick={toggleOriginalPlay}
          className="shrink-0 flex items-center gap-1.5 text-xs text-gray-400 hover:text-white bg-slate-800 hover:bg-slate-700 px-3 py-2 rounded-lg transition-colors"
        >
          {isPlaying ? <Pause size={13} /> : <Play size={13} />}
          {isPlaying ? 'Pause' : 'Play original'}
        </button>
      </div>

      {/* Language badge */}
      {language && (
          <span className="inline-flex items-center gap-1 text-xs bg-slate-800 text-gray-400 px-2.5 py-1 rounded-full border border-slate-700">
          Detected language: <span className="font-medium text-gray-200 uppercase">{language}</span>
        </span>
      )}

      {/* Single editable transcript */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <label className="text-sm font-medium text-gray-300 flex items-center gap-2">
            {isImproved && <Wand2 size={13} className="text-pink-400" />}
            {isImproved ? 'AI-Improved Transcript' : 'Transcript'}
          </label>
          {isImproved && (
            <button
              onClick={handleRestoreOriginal}
              className="flex items-center gap-1 text-xs text-gray-500 hover:text-gray-300 transition-colors"
            >
              <RotateCcw size={11} />
              Restore Whisper original
            </button>
          )}
        </div>
        <textarea
          value={transcript}
          onChange={(e) => { setTranscript(e.target.value); setIsImproved(false) }}
          disabled={isImproving}
          rows={9}
          className={[
            'w-full bg-slate-950 border rounded-xl px-4 py-3 text-gray-200 text-sm leading-relaxed resize-none',
            'focus:outline-none transition-colors placeholder-gray-600 disabled:opacity-60 disabled:cursor-not-allowed',
            isImproved ? 'border-pink-500' : 'border-slate-700 focus:border-pink-600',
          ].join(' ')}
          placeholder="Transcript will appear here…"
        />
      </div>

      {/* Improving status */}
      {isImproving && (
        <div className="flex items-center gap-2 text-sm text-pink-400">
          <span className="w-4 h-4 rounded-full border-2 border-pink-400 border-t-transparent animate-spin shrink-0" />
          Sending to Ollama (mistral)… this may take 10–30 seconds.
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="text-sm text-red-400 bg-red-950/30 border border-red-800 rounded-xl px-4 py-3">
          {error}
        </div>
      )}

      {/* Speaking style selector */}
      {stylePresets.length > 0 && (
        <div className="space-y-3">
          <div>
            <p className="text-sm font-medium text-gray-300">Speaking Style</p>
            <p className="text-xs text-gray-500 mt-0.5">
              Choose how the synthesised voice will sound. Your cloned voice is preserved in all styles.
            </p>
          </div>
          {(() => {
            const groups = {}
            stylePresets.forEach((p) => {
              const g = p.group || 'Other'
              if (!groups[g]) groups[g] = []
              groups[g].push(p)
            })
            return Object.entries(groups).map(([group, presets]) => (
              <div key={group} className="space-y-1.5">
                <p className="text-xs font-semibold text-gray-600 uppercase tracking-widest">{group}</p>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                  {presets.map((preset) => {
                    const isSelected = selectedStyle === preset.id
                    return (
                      <button
                        key={preset.id}
                        onClick={() => setSelectedStyle(preset.id)}
                        className={[
                          'flex flex-col items-start gap-0.5 px-4 py-3 rounded-xl border text-left transition-all',
                          isSelected
                            ? 'border-pink-500 bg-pink-950/40 ring-1 ring-pink-500'
                            : 'border-slate-700 bg-slate-800/50 hover:border-slate-600',
                        ].join(' ')}
                      >
                        <span className={`text-sm font-medium ${isSelected ? 'text-pink-300' : 'text-gray-200'}`}>
                          {preset.label}
                        </span>
                        <span className="text-xs text-gray-500 leading-snug">{preset.description}</span>
                        <span className={`text-xs mt-1 tabular-nums ${isSelected ? 'text-pink-400' : 'text-gray-600'}`}>
                          {preset.speed < 1 ? `${preset.speed}× speed` : preset.speed > 1 ? `${preset.speed}× speed` : 'Normal speed'}
                        </span>
                      </button>
                    )
                  })}
                </div>
              </div>
            ))
          })()}
        </div>
      )}

      {/* Actions */}
      <div className="flex items-center gap-3">
        {/* Improve with AI — always available */}
        <button
          onClick={runImprovement}
          disabled={isImproving || !transcript.trim()}
          className="flex items-center gap-2 px-5 py-2.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-xl font-medium transition-colors"
        >
          {isImproving ? (
            <>
              <span className="w-4 h-4 rounded-full border-2 border-white border-t-transparent animate-spin" />
              Improving…
            </>
          ) : (
            <>
              <Wand2 size={17} />
              Improve with AI
            </>
          )}
        </button>

        {/* Continue */}
        <button
          onClick={handleFinalize}
          disabled={!transcript.trim() || isImproving}
          className="ml-auto flex items-center gap-2 px-5 py-2.5 bg-pink-600 hover:bg-pink-500 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-xl font-medium transition-colors"
        >
          Continue to Synthesis
          <ChevronRight size={17} />
        </button>
      </div>
    </div>
  )
}
