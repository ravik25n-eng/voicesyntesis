import { useState, useEffect, useRef } from 'react'
import { Plus, RefreshCw, FolderOpen, Mic2, Volume2, Calendar, Play, Pause, Trash2 } from 'lucide-react'
import { listProjects, deleteProject } from '../api/client'

function formatDate(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}

export default function ProjectList({ onNewProject, onOpenProject }) {
  const [projects, setProjects] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [playingId, setPlayingId] = useState(null)
  const [deletingId, setDeletingId] = useState(null)
  const audioRef = useRef(null)

  const load = async () => {
    setLoading(true)
    setError(null)
    try {
      const data = await listProjects()
      setProjects(data)
    } catch {
      setError('Could not load projects. Is the backend running?')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const handleDelete = async (p) => {
    if (!window.confirm(`Delete "${p.name}"? This cannot be undone.`)) return
    setDeletingId(p.project_id)
    try {
      await deleteProject(p.project_id)
      setProjects((prev) => prev.filter((x) => x.project_id !== p.project_id))
    } catch {
      alert('Failed to delete project. Please try again.')
    } finally {
      setDeletingId(null)
    }
  }

  const handlePreview = (url, id) => {
    if (!url) return
    if (playingId === id) {
      audioRef.current?.pause()
      setPlayingId(null)
      return
    }
    if (audioRef.current) audioRef.current.pause()
    const audio = new Audio(url)
    audioRef.current = audio
    audio.onended = () => setPlayingId(null)
    audio.play()
    setPlayingId(id)
  }

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-semibold text-white">Voice Projects</h2>
          <p className="text-sm text-slate-400 mt-0.5">Each project stores a voice sample and synthesised outputs.</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={load}
            disabled={loading}
            className="p-2 rounded-lg text-slate-500 hover:text-slate-300 hover:bg-slate-800 transition-colors disabled:opacity-40"
            title="Refresh"
          >
            <RefreshCw size={15} className={loading ? 'animate-spin' : ''} />
          </button>
          <button
            onClick={onNewProject}
            className="flex items-center gap-2 px-4 py-2 bg-pink-600 hover:bg-pink-500 text-white rounded-xl text-sm font-medium transition-colors"
          >
            <Plus size={15} />
            New Project
          </button>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="text-sm text-red-400 bg-red-950/30 border border-red-800 rounded-xl px-4 py-3">
          {error}
        </div>
      )}

      {/* Loading skeleton */}
      {loading && !error && (
        <div className="space-y-3">
          {[1, 2].map((i) => (
            <div key={i} className="bg-slate-900 border border-slate-800 rounded-2xl p-5 animate-pulse">
              <div className="h-4 bg-slate-700 rounded w-1/3 mb-2" />
              <div className="h-3 bg-slate-800 rounded w-1/5" />
            </div>
          ))}
        </div>
      )}

      {/* Empty state */}
      {!loading && !error && projects.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center space-y-4">
          <div className="w-14 h-14 rounded-2xl bg-slate-800 border border-slate-700 flex items-center justify-center">
            <Mic2 size={24} className="text-pink-500/60" />
          </div>
          <div>
            <p className="text-white font-medium">No projects yet</p>
            <p className="text-sm text-slate-500 mt-1">Create your first voice project to get started.</p>
          </div>
          <button
            onClick={onNewProject}
            className="flex items-center gap-2 px-5 py-2.5 bg-pink-600 hover:bg-pink-500 text-white rounded-xl text-sm font-medium transition-colors"
          >
            <Plus size={16} />
            Create First Project
          </button>
        </div>
      )}

      {/* Project cards */}
      {!loading && projects.length > 0 && (
        <div className="space-y-3">
          {projects.map((p) => (
            <div
              key={p.project_id}
              className="bg-slate-900 border border-slate-800 rounded-2xl p-5 flex items-center gap-4 hover:border-slate-700 transition-colors"
            >
              {/* Icon */}
              <div className="w-10 h-10 rounded-xl bg-slate-800 border border-slate-700 flex items-center justify-center shrink-0">
                <Mic2 size={18} className="text-pink-400/70" />
              </div>

              {/* Info */}
              <div className="flex-1 min-w-0">
                <p className="text-white font-medium truncate">{p.name}</p>
                <div className="flex flex-wrap items-center gap-2 mt-1.5">
                  <span className="flex items-center gap-1 text-xs text-slate-500">
                    <Calendar size={11} />
                    {formatDate(p.created_at)}
                  </span>
                  {p.has_recording && (
                    <span className="flex items-center gap-1 text-xs bg-slate-800 text-slate-300 px-2 py-0.5 rounded-full border border-slate-700">
                      <Mic2 size={10} className="text-pink-400/70" />
                      Voice recorded
                    </span>
                  )}
                  {p.has_output && (
                    <span className="flex items-center gap-1 text-xs bg-pink-950/50 text-pink-300 px-2 py-0.5 rounded-full border border-pink-800/40">
                      <Volume2 size={10} />
                      Output ready
                    </span>
                  )}
                </div>
              </div>

              {/* Preview buttons */}
              <div className="flex items-center gap-2 shrink-0">
                {p.has_recording && p.recording_url && (
                  <button
                    onClick={() => handlePreview(p.recording_url, `rec-${p.project_id}`)}
                    className="p-2 rounded-lg text-slate-500 hover:text-white hover:bg-slate-800 transition-colors"
                    title="Preview recording"
                  >
                    {playingId === `rec-${p.project_id}` ? <Pause size={14} /> : <Play size={14} />}
                  </button>
                )}
                {p.has_output && p.output_url && (
                  <button
                    onClick={() => handlePreview(p.output_url, `out-${p.project_id}`)}
                    className="p-2 rounded-lg text-pink-400/70 hover:text-pink-400 hover:bg-slate-800 transition-colors"
                    title="Preview synthesised output"
                  >
                    {playingId === `out-${p.project_id}` ? <Pause size={14} /> : <Volume2 size={14} />}
                  </button>
                )}
                <button
                  onClick={() => onOpenProject(p)}
                  className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 border border-slate-700 text-white rounded-lg text-xs font-medium transition-colors"
                >
                  <FolderOpen size={13} />
                  Continue
                </button>
                <button
                  onClick={() => handleDelete(p)}
                  disabled={deletingId === p.project_id}
                  className="p-2 rounded-lg text-slate-600 hover:text-red-400 hover:bg-red-950/30 transition-colors disabled:opacity-40"
                  title="Delete project"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
