import { useQuery } from '@tanstack/react-query'
import { Link, useParams } from 'react-router-dom'
import { useState } from 'react'
import { algorithmsApi } from '../../api/algorithms'

export default function AlgorithmDetail() {
  const { key } = useParams<{ key: string }>()
  const [step, setStep] = useState(0)

  const { data, isLoading } = useQuery({
    queryKey: ['algorithms', key],
    queryFn: () => algorithmsApi.detail(key!),
    enabled: !!key,
  })

  if (isLoading) return <div className="text-gray-500">Загрузка...</div>
  if (!data) return <div className="text-red-700">Не найдено</div>

  const current = data.steps[step]
  const total = data.steps.length

  return (
    <div className="space-y-4">
      <nav className="text-sm">
        <Link to="/algorithms" className="text-blue-600 hover:underline">
          ← К списку алгоритмов
        </Link>
      </nav>
      <h1 className="text-2xl font-bold">{data.title}</h1>

      <div className="bg-white rounded-lg shadow p-5">
        <div className="text-xs text-gray-500 mb-2">
          Шаг {step + 1} из {total}
        </div>
        <h2 className="text-lg font-semibold mb-2">{current.title}</h2>
        <pre className="whitespace-pre-wrap text-sm font-sans text-gray-800">
          {current.text}
        </pre>
      </div>

      <div className="flex justify-between items-center">
        <button
          disabled={step === 0}
          onClick={() => setStep(step - 1)}
          className="px-3 py-1.5 bg-white border rounded disabled:opacity-40 hover:bg-gray-100"
        >
          ← Назад
        </button>
        <span className="text-sm text-gray-500">
          {step + 1} / {total}
        </span>
        <button
          disabled={step >= total - 1}
          onClick={() => setStep(step + 1)}
          className="px-3 py-1.5 bg-white border rounded disabled:opacity-40 hover:bg-gray-100"
        >
          Далее →
        </button>
      </div>
    </div>
  )
}
