import { Check } from 'lucide-react'

/**
 * Horizontal step indicator showing pipeline progress.
 * steps: [{ id, label }]
 * currentStep: number (1-based)
 */
export default function StepIndicator({ steps, currentStep }) {
  return (
    <nav aria-label="Pipeline progress">
      <ol className="flex items-center">
        {steps.map((step, idx) => {
          const isDone = step.id < currentStep
          const isActive = step.id === currentStep
          const isLast = idx === steps.length - 1

          return (
            <li key={step.id} className="flex items-center flex-1">
              <div className="flex flex-col items-center gap-1.5">
                <div
                  className={[
                    'w-9 h-9 rounded-full flex items-center justify-center text-sm font-semibold border-2 transition-all duration-300',
                    isDone && 'bg-pink-600 border-pink-600 text-white',
                    isActive && 'bg-transparent border-pink-400 text-pink-400 shadow-[0_0_12px_2px_rgba(236,72,153,0.3)]',
                    !isDone && !isActive && 'bg-transparent border-slate-700 text-slate-600',
                  ]
                    .filter(Boolean)
                    .join(' ')}
                >
                  {isDone ? <Check size={16} strokeWidth={2.5} /> : step.id}
                </div>
                <span
                  className={[
                    'text-xs whitespace-nowrap font-medium',
                    isActive && 'text-pink-400',
                    isDone && 'text-gray-500',
                    !isDone && !isActive && 'text-slate-700',
                  ]
                    .filter(Boolean)
                    .join(' ')}
                >
                  {step.label}
                </span>
              </div>

              {/* Connector line */}
              {!isLast && (
                <div
                  className={[
                    'flex-1 h-px mx-3 mb-5 transition-all duration-500',
                    isDone ? 'bg-pink-600' : 'bg-slate-800',
                  ].join(' ')}
                />
              )}
            </li>
          )
        })}
      </ol>
    </nav>
  )
}
