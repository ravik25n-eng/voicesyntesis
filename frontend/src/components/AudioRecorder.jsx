import { useState, useRef, useCallback, useEffect } from 'react'
import { Mic, Square, Play, Pause, RotateCcw, ArrowRight, Upload, FileAudio } from 'lucide-react'
import { uploadAudio } from '../api/client'

const MIN_DURATION = 30
const MAX_DURATION = 120

function formatTime(seconds) {
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}:${String(s).padStart(2, '0')}`
}

const ACCEPTED_AUDIO = ['audio/wav', 'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/ogg', 'audio/flac', 'audio/webm']
const ACCEPTED_EXT = '.wav,.mp3,.m4a,.ogg,.flac,.webm'

export default function AudioRecorder({ onComplete, projectId }) {
  // ── Tab ───────────────────────────────────────────────────────────────────
  const [tab, setTab] = useState('record') // 'record' | 'upload'

  // ── Record state ──────────────────────────────────────────────────────────
  const [duration, setDuration] = useState(30)
  const [phase, setPhase] = useState('idle') // idle | recording | recorded | uploading
  const [elapsed, setElapsed] = useState(0)
  const [audioBlob, setAudioBlob] = useState(null)
  const [localAudioUrl, setLocalAudioUrl] = useState(null)
  const [isPlaying, setIsPlaying] = useState(false)
  const [error, setError] = useState(null)

  // ── Upload state ──────────────────────────────────────────────────────────
  const [uploadFile, setUploadFile] = useState(null)       // File object
  const [uploadPreviewUrl, setUploadPreviewUrl] = useState(null)
  const [uploadPhase, setUploadPhase] = useState('idle')   // idle | ready | uploading
  const [uploadError, setUploadError] = useState(null)
  const [isDragging, setIsDragging] = useState(false)
  const fileInputRef = useRef(null)

  const mediaRecorderRef = useRef(null)
  const chunksRef = useRef([])
  const streamRef = useRef(null)
  const audioCtxRef = useRef(null)
  const analyserRef = useRef(null)
  const canvasRef = useRef(null)
  const animFrameRef = useRef(null)
  const timerRef = useRef(null)
  const audioElRef = useRef(null)

  // ── Waveform canvas ───────────────────────────────────────────────────────

  const drawWaveform = useCallback(() => {
    const canvas = canvasRef.current
    const analyser = analyserRef.current
    if (!canvas || !analyser) return

    const ctx = canvas.getContext('2d')
    const bufferLength = analyser.frequencyBinCount
    const dataArray = new Uint8Array(bufferLength)

    const draw = () => {
      animFrameRef.current = requestAnimationFrame(draw)
      analyser.getByteTimeDomainData(dataArray)

      ctx.clearRect(0, 0, canvas.width, canvas.height)
      ctx.lineWidth = 2
      ctx.strokeStyle = '#ec4899'
      ctx.shadowColor = '#ec489980'
      ctx.shadowBlur = 6
      ctx.beginPath()

      const sliceWidth = canvas.width / bufferLength
      let x = 0
      for (let i = 0; i < bufferLength; i++) {
        const v = dataArray[i] / 128.0
        const y = (v * canvas.height) / 2
        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
        x += sliceWidth
      }
      ctx.lineTo(canvas.width, canvas.height / 2)
      ctx.stroke()
    }
    draw()
  }, [])

  const stopAnimation = useCallback(() => {
    if (animFrameRef.current) {
      cancelAnimationFrame(animFrameRef.current)
      animFrameRef.current = null
    }
    // Draw idle flat line
    const canvas = canvasRef.current
    if (canvas) {
      const ctx = canvas.getContext('2d')
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      ctx.lineWidth = 1
      ctx.strokeStyle = '#374151'
      ctx.shadowBlur = 0
      ctx.beginPath()
      ctx.moveTo(0, canvas.height / 2)
      ctx.lineTo(canvas.width, canvas.height / 2)
      ctx.stroke()
    }
  }, [])

  // Draw idle line on mount
  useEffect(() => {
    stopAnimation()
    return () => stopAnimation()
  }, [stopAnimation])

  // ── Recording control ────────────────────────────────────────────────────

  const stopRecording = useCallback(() => {
    clearInterval(timerRef.current)
    timerRef.current = null

    if (mediaRecorderRef.current?.state === 'recording') {
      mediaRecorderRef.current.stop()
    }
    streamRef.current?.getTracks().forEach((t) => t.stop())
    audioCtxRef.current?.close()
    stopAnimation()
    setPhase('recorded')
  }, [stopAnimation])

  const startRecording = async () => {
    setError(null)
    setAudioBlob(null)
    setLocalAudioUrl(null)
    chunksRef.current = []
    setElapsed(0)

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      streamRef.current = stream

      // Waveform analyser
      const audioCtx = new AudioContext()
      audioCtxRef.current = audioCtx
      const source = audioCtx.createMediaStreamSource(stream)
      const analyser = audioCtx.createAnalyser()
      analyser.fftSize = 2048
      source.connect(analyser)
      analyserRef.current = analyser
      drawWaveform()

      const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
        ? 'audio/webm;codecs=opus'
        : 'audio/webm'

      const recorder = new MediaRecorder(stream, { mimeType })
      mediaRecorderRef.current = recorder

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data)
      }

      recorder.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: mimeType })
        setAudioBlob(blob)
        setLocalAudioUrl(URL.createObjectURL(blob))
      }

      recorder.start(100) // collect data every 100ms
      setPhase('recording')

      // Countdown timer — auto-stop at duration
      timerRef.current = setInterval(() => {
        setElapsed((prev) => {
          const next = prev + 1
          if (next >= duration) {
            stopRecording()
          }
          return next
        })
      }, 1000)
    } catch {
      setError('Microphone access was denied. Please allow microphone access and try again.')
    }
  }

  const handleReset = () => {
    stopAnimation()
    setPhase('idle')
    setElapsed(0)
    setAudioBlob(null)
    setLocalAudioUrl(null)
    setIsPlaying(false)
    setError(null)
  }

  const togglePlayback = () => {
    if (!localAudioUrl) return
    if (!audioElRef.current) {
      audioElRef.current = new Audio(localAudioUrl)
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

  const handleUpload = async () => {
    if (!audioBlob) return
    setPhase('uploading')
    setError(null)
    try {
      const result = await uploadAudio(projectId, audioBlob)
      onComplete({ fileId: result.file_id, audioUrl: result.audio_url })
    } catch (err) {
      setError(err?.response?.data?.detail ?? 'Upload failed. Is the backend running on port 8000?')
      setPhase('recorded')
    }
  }

  // ── File upload handlers ──────────────────────────────────────────────────

  const handleFileSelect = (file) => {
    setUploadError(null)
    if (!file) return

    const isAudio = ACCEPTED_AUDIO.includes(file.type) || file.name.match(/\.(wav|mp3|m4a|ogg|flac|webm)$/i)
    if (!isAudio) {
      setUploadError('Unsupported format. Please use WAV, MP3, M4A, OGG, FLAC, or WebM.')
      return
    }
    if (file.size > 150 * 1024 * 1024) {
      setUploadError('File is too large. Maximum size is 150 MB.')
      return
    }
    setUploadFile(file)
    setUploadPreviewUrl(URL.createObjectURL(file))
    setUploadPhase('ready')
  }

  const handleFileInputChange = (e) => handleFileSelect(e.target.files?.[0])

  const handleDrop = (e) => {
    e.preventDefault()
    setIsDragging(false)
    handleFileSelect(e.dataTransfer.files?.[0])
  }

  const handleFileUploadSubmit = async () => {
    if (!uploadFile) return
    setUploadPhase('uploading')
    setUploadError(null)
    try {
      const result = await uploadAudio(projectId, uploadFile)
      onComplete({ fileId: result.file_id, audioUrl: result.audio_url })
    } catch (err) {
      setUploadError(err?.response?.data?.detail ?? 'Upload failed. Is the backend running on port 8000?')
      setUploadPhase('ready')
    }
  }

  const handleFileReset = () => {
    setUploadFile(null)
    setUploadPreviewUrl(null)
    setUploadPhase('idle')
    setUploadError(null)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  const progress = phase === 'recording' ? (elapsed / duration) * 100 : 0

  // ── Render ───────────────────────────────────────────────────────────────

  return (
    <div className="bg-slate-900 rounded-2xl p-6 border border-slate-800 space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-lg font-semibold text-white mb-1">Voice Sample</h2>
        <p className="text-sm text-gray-400">
          Provide a clear voice sample — record live or upload an existing file.
        </p>
      </div>

      {/* Tab switcher */}
      <div className="flex gap-1 bg-slate-800 rounded-xl p-1">
        <button
          onClick={() => { setTab('record'); setError(null) }}
          className={`flex-1 flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
            tab === 'record' ? 'bg-pink-600 text-white' : 'text-gray-400 hover:text-white'
          }`}
        >
          <Mic size={15} />
          Record
        </button>
        <button
          onClick={() => { setTab('upload'); setError(null) }}
          className={`flex-1 flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
            tab === 'upload' ? 'bg-pink-600 text-white' : 'text-gray-400 hover:text-white'
          }`}
        >
          <Upload size={15} />
          Upload File
        </button>
      </div>

      {/* ── RECORD TAB ── */}
      {tab === 'record' && (
        <>
          {/* Duration slider */}
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <label className="text-gray-400 font-medium">Recording Duration</label>
              <span className="text-pink-400 font-semibold tabular-nums">{formatTime(duration)}</span>
            </div>
            <input
              type="range"
              min={MIN_DURATION}
              max={MAX_DURATION}
              step={10}
              value={duration}
              disabled={phase === 'recording'}
              onChange={(e) => {
                setDuration(Number(e.target.value))
                handleReset()
              }}
              className="w-full h-2 rounded-full appearance-none cursor-pointer bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50"
            />
            <div className="flex justify-between text-xs text-gray-600">
              <span>{formatTime(MIN_DURATION)}</span>
              <span>{formatTime(MAX_DURATION)}</span>
            </div>
          </div>

          {/* Waveform */}
          <div className="bg-slate-950 rounded-xl border border-slate-800 px-3 py-2">
            <canvas ref={canvasRef} width={640} height={72} className="w-full" />
          </div>

          {/* Recording progress bar */}
          {phase === 'recording' && (
            <div className="space-y-1.5">
              <div className="flex justify-between text-xs text-gray-400">
                <span className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse shrink-0" />
                  Recording in progress…
                </span>
                <span className="tabular-nums">
                  {formatTime(elapsed)} / {formatTime(duration)}
                </span>
              </div>
              <div className="w-full h-1.5 bg-slate-800 rounded-full overflow-hidden">
                <div
                  className="h-full bg-pink-500 rounded-full transition-all duration-1000 ease-linear"
                  style={{ width: `${progress}%` }}
                />
              </div>
            </div>
          )}

          {/* Recorded preview */}
          {phase === 'recorded' && localAudioUrl && (
            <div className="flex items-center gap-3 bg-slate-800 rounded-xl px-4 py-3">
              <button
                onClick={togglePlayback}
                className="p-2 rounded-full bg-pink-700 hover:bg-pink-600 transition-colors"
                aria-label={isPlaying ? 'Pause preview' : 'Play preview'}
              >
                {isPlaying ? <Pause size={15} /> : <Play size={15} />}
              </button>
              <div className="flex-1">
                <p className="text-sm text-white font-medium">Recording ready</p>
                <p className="text-xs text-gray-400">{elapsed}s captured</p>
              </div>
            </div>
          )}

          {/* Error */}
          {error && (
            <div className="text-sm text-red-400 bg-red-950/30 border border-red-800 rounded-xl px-4 py-3">
              {error}
            </div>
          )}

          {/* Record action buttons */}
          <div className="flex gap-3">
            {phase === 'idle' && (
              <button
                onClick={startRecording}
                className="flex items-center gap-2 px-5 py-2.5 bg-pink-600 hover:bg-pink-500 text-white rounded-xl font-medium transition-colors"
              >
                <Mic size={17} />
                Start Recording
              </button>
            )}

            {phase === 'recording' && (
              <button
                onClick={stopRecording}
                className="flex items-center gap-2 px-5 py-2.5 bg-red-600 hover:bg-red-500 text-white rounded-xl font-medium transition-colors"
              >
                <Square size={17} />
                Stop Recording
              </button>
            )}

            {phase === 'recorded' && (
              <>
                <button
                  onClick={handleReset}
                  className="flex items-center gap-2 px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl font-medium transition-colors"
                >
                  <RotateCcw size={17} />
                  Re-record
                </button>
                <button
                  onClick={handleUpload}
                  className="ml-auto flex items-center gap-2 px-5 py-2.5 bg-pink-600 hover:bg-pink-500 text-white rounded-xl font-medium transition-colors"
                >
                  Use This Recording
                  <ArrowRight size={17} />
                </button>
              </>
            )}

            {phase === 'uploading' && (
              <button disabled className="flex items-center gap-2 px-5 py-2.5 bg-pink-600 opacity-60 text-white rounded-xl font-medium cursor-not-allowed">
                <span className="w-4 h-4 rounded-full border-2 border-white border-t-transparent animate-spin" />
                Uploading…
              </button>
            )}
          </div>
        </>
      )}

      {/* ── UPLOAD TAB ── */}
      {tab === 'upload' && (
        <>
          {uploadPhase === 'idle' && (
            <>
              {/* Drop zone */}
              <div
                onDragOver={(e) => { e.preventDefault(); setIsDragging(true) }}
                onDragLeave={() => setIsDragging(false)}
                onDrop={handleDrop}
                onClick={() => fileInputRef.current?.click()}
                className={`flex flex-col items-center justify-center gap-3 border-2 border-dashed rounded-xl px-6 py-10 cursor-pointer transition-colors ${
                  isDragging
                    ? 'border-pink-500 bg-pink-950/20'
                    : 'border-slate-700 hover:border-pink-600 hover:bg-slate-800/50'
                }`}
              >
                <FileAudio size={36} className="text-gray-500" />
                <div className="text-center">
                  <p className="text-sm text-white font-medium">Drop an audio file here</p>
                  <p className="text-xs text-gray-500 mt-1">or click to browse</p>
                </div>
                <p className="text-xs text-gray-600">WAV · MP3 · M4A · OGG · FLAC · WebM · up to 150 MB</p>
              </div>
              <input
                ref={fileInputRef}
                type="file"
                accept={ACCEPTED_EXT}
                className="hidden"
                onChange={handleFileInputChange}
              />
            </>
          )}

          {uploadPhase === 'ready' && uploadFile && (
            <>
              {/* File preview */}
              <div className="bg-slate-800 rounded-xl px-4 py-4 space-y-3">
                <div className="flex items-center gap-3">
                  <FileAudio size={22} className="text-pink-400 shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-white font-medium truncate">{uploadFile.name}</p>
                    <p className="text-xs text-gray-400">{(uploadFile.size / (1024 * 1024)).toFixed(2)} MB</p>
                  </div>
                </div>
                {uploadPreviewUrl && (
                  <audio controls src={uploadPreviewUrl} className="w-full h-8 rounded" />
                )}
              </div>

              <div className="flex gap-3">
                <button
                  onClick={handleFileReset}
                  className="flex items-center gap-2 px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl font-medium transition-colors"
                >
                  <RotateCcw size={17} />
                  Choose different file
                </button>
                <button
                  onClick={handleFileUploadSubmit}
                  className="ml-auto flex items-center gap-2 px-5 py-2.5 bg-pink-600 hover:bg-pink-500 text-white rounded-xl font-medium transition-colors"
                >
                  Use This File
                  <ArrowRight size={17} />
                </button>
              </div>
            </>
          )}

          {uploadPhase === 'uploading' && (
            <div className="flex items-center gap-3 py-4 text-pink-400">
              <span className="w-5 h-5 rounded-full border-2 border-pink-400 border-t-transparent animate-spin shrink-0" />
              <span className="text-sm">Uploading and converting audio…</span>
            </div>
          )}

          {uploadError && (
            <div className="text-sm text-red-400 bg-red-950/30 border border-red-800 rounded-xl px-4 py-3">
              {uploadError}
            </div>
          )}
        </>
      )}
    </div>
  )
}
