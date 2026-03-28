import { useState } from 'react'
import { Mic2, ArrowLeft } from 'lucide-react'
import StepIndicator from './components/StepIndicator'
import AudioRecorder from './components/AudioRecorder'
import TranscriptEditor from './components/TranscriptEditor'
import VoiceSynthesizer from './components/VoiceSynthesizer'
import ProjectList from './components/ProjectList'
import { createProject } from './api/client'

const STEPS = [
  { id: 1, label: 'Record' },
  { id: 2, label: 'Refine Transcript' },
  { id: 3, label: 'Synthesise' },
]

export default function App() {
  const [view, setView] = useState('list') // 'list' | 'new' | 'pipeline'
  const [step, setStep] = useState(1)
  const [projectId, setProjectId] = useState(null)
  const [projectName, setProjectName] = useState('')
  const [finalTranscript, setFinalTranscript] = useState('')
  const [selectedStyle, setSelectedStyle] = useState('standard')
  const [nameInput, setNameInput] = useState('')
  const [nameError, setNameError] = useState('')
  const [creating, setCreating] = useState(false)

  const handleNewProject = () => {
    setNameInput('')
    setNameError('')
    setView('new')
  }

  const handleCreateProject = async (e) => {
    e.preventDefault()
    const name = nameInput.trim()
    if (!name) { setNameError('Please enter a project name.'); return }
    setCreating(true)
    setNameError('')
    try {
      const result = await createProject(name)
      setProjectId(result.project_id)
      setProjectName(result.name)
      setStep(1)
      setFinalTranscript('')
      setView('pipeline')
    } catch (err) {
      setNameError(err?.response?.data?.detail ?? 'Could not create project. Is the backend running?')
    } finally {
      setCreating(false)
    }
  }

  const handleOpenProject = (project) => {
    setProjectId(project.project_id)
    setProjectName(project.name)
    setFinalTranscript('')
    setStep(project.has_recording ? 2 : 1)
    setView('pipeline')
  }

  const handleRecordingComplete = ({ fileId }) => {
    setProjectId(fileId)
    setStep(2)
  }

  const handleTranscriptFinalized = ({ final, style }) => {
    setFinalTranscript(final)
    setSelectedStyle(style ?? 'standard')
    setStep(3)
  }

  const handleReset = () => {
    setView('list')
    setProjectId(null)
    setProjectName('')
    setFinalTranscript('')
    setSelectedStyle('standard')
    setStep(1)
  }

  return (
    <div className="min-h-screen flex flex-col">
      {/* Header */}
      <header className="border-b border-slate-800 px-6 py-4 sticky top-0 bg-slate-950/90 backdrop-blur z-10">
        <div className="max-w-3xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2">
              <h1 className="text-lg font-semibold text-white tracking-tight">Voice Syntesis</h1>
            </div>
          </div>
          {(view === 'pipeline' || view === 'new') && (
            <button
              onClick={() => setView('list')}
              className="flex items-center gap-1.5 text-xs text-gray-500 hover:text-gray-300 transition-colors"
            >
              <ArrowLeft size={13} />
              All projects
            </button>
          )}
        </div>
      </header>

      {/* Main content */}
      <main className="flex-1 max-w-3xl mx-auto w-full px-4 sm:px-6 py-8 space-y-8">

        {/* PROJECT LIST VIEW */}
        {view === 'list' && (
          <ProjectList onNewProject={handleNewProject} onOpenProject={handleOpenProject} />
        )}

        {/* NEW PROJECT NAME INPUT */}
        {view === 'new' && (
          <div className="space-y-6">
            <div>
              <h2 className="text-xl font-semibold text-white">New Voice Project</h2>
              <p className="text-sm text-gray-400 mt-1">Give your voice a name before recording or uploading.</p>
            </div>
            <form onSubmit={handleCreateProject} className="bg-slate-900 border border-slate-800 rounded-2xl p-6 space-y-4">
              <div className="space-y-2">
                <label htmlFor="project-name" className="text-sm font-medium text-gray-300">
                  Project Name
                </label>
                <input
                  id="project-name"
                  type="text"
                  value={nameInput}
                  onChange={(e) => { setNameInput(e.target.value); setNameError('') }}
                  placeholder="e.g. My Voice, Narrator, Alex"
                  autoFocus
                  maxLength={80}
                  className="w-full bg-slate-800 border border-slate-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-pink-600 focus:border-transparent"
                />
                {nameError && <p className="text-sm text-red-400">{nameError}</p>}
              </div>
              <div className="flex gap-3 justify-end">
                <button
                  type="button"
                  onClick={() => setView('list')}
                  className="px-4 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl text-sm font-medium transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={creating}
                  className="flex items-center gap-2 px-5 py-2.5 bg-pink-600 hover:bg-pink-500 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  {creating
                    ? <><span className="w-4 h-4 rounded-full border-2 border-white border-t-transparent animate-spin" />Creating…</>
                    : 'Create Project →'
                  }
                </button>
              </div>
            </form>
          </div>
        )}

        {/* PIPELINE VIEW */}
        {view === 'pipeline' && (
          <>
            {projectName && (
              <div className="flex items-center gap-2">
                <span className="text-sm text-gray-500">Project:</span>
                <span className="text-sm font-medium text-pink-300">{projectName}</span>
              </div>
            )}

            <StepIndicator steps={STEPS} currentStep={step} />

            {step === 1 && (
              <AudioRecorder projectId={projectId} onComplete={handleRecordingComplete} />
            )}

            {step === 2 && (
              <TranscriptEditor fileId={projectId} onFinalized={handleTranscriptFinalized} />
            )}

            {step === 3 && (
              <VoiceSynthesizer
                fileId={projectId}
                genText={finalTranscript}
                style={selectedStyle}
                onReset={handleReset}
              />
            )}
          </>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-slate-800 px-6 py-4 text-center text-xs text-slate-600 space-y-1">
      </footer>
    </div>
  )
}
