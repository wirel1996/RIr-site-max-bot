import { useMutation } from '@tanstack/react-query'
import { useMemo, useState, type FormEvent } from 'react'
import { calcApi, type VolumeForm } from '../../api/calc'

const FIELDS: { key: keyof VolumeForm; label: string; placeholder?: string }[] = [
  { key: 'h', label: 'Н, м (высота)' },
  { key: 'v', label: 'V, куб.м' },
  { key: 'q', label: 'q, ккал/куб.м·час·град' },
  { key: 't_vn', label: 't, вн.' },
  { key: 'v_podval', label: 'V подвал' },
]

export default function VolumeCalc() {
  const [form, setForm] = useState<VolumeForm>({
    h: '',
    v: '',
    q: '',
    t_vn: '',
    v_podval: '',
  })
  const [diaphragmForm, setDiaphragmForm] = useState({
    pressureDrop: '',
    heatingLoad: '',
  })

  const mutate = useMutation({
    mutationFn: (f: VolumeForm) => calcApi.volume(f),
  })

  const diaphragmResult = useMemo(() => {
    const pressureDrop = parseDecimal(diaphragmForm.pressureDrop)
    const heatingLoad = parseDecimal(diaphragmForm.heatingLoad)
    if (pressureDrop === null || heatingLoad === null) return null
    if (pressureDrop <= 0 || heatingLoad <= 0) return null

    const rounded = diaphragmValue(heatingLoad, pressureDrop)
    const diameter = Math.max(3, rounded)
    const washers =
      rounded > 3
        ? '1 шайба'
        : `2 шайбы по ${formatOneDecimal(Math.max(3, diaphragmValue(heatingLoad, pressureDrop / 2)))}`

    return { diameter, washers }
  }, [diaphragmForm])

  const onSubmit = (e: FormEvent) => {
    e.preventDefault()
    mutate.mutate(form)
  }

  const onClear = () => {
    setForm({ h: '', v: '', q: '', t_vn: '', v_podval: '' })
    mutate.reset()
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <h1 className="text-2xl font-bold">🧮 Расчёт тепловой нагрузки</h1>

      <form onSubmit={onSubmit} className="bg-white rounded-lg shadow p-5 space-y-3">
        {FIELDS.map((f) => (
          <label key={f.key} className="flex items-center gap-3">
            <span className="w-64 text-sm text-gray-700 shrink-0">{f.label}</span>
            <input
              type="text"
              inputMode="decimal"
              value={form[f.key]}
              onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
              className="border rounded px-2 py-1 flex-1"
              placeholder={f.placeholder}
            />
          </label>
        ))}

        <div className="flex gap-2 pt-2">
          <button
            type="submit"
            disabled={mutate.isPending}
            className="bg-blue-600 text-white px-4 py-1.5 rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {mutate.isPending ? 'Считаю...' : 'Рассчитать Qот'}
          </button>
          <button
            type="button"
            onClick={onClear}
            className="bg-white border px-4 py-1.5 rounded hover:bg-gray-100"
          >
            Очистить
          </button>
        </div>
      </form>

      {mutate.data && (
        <div className="bg-white rounded-lg shadow p-5">
          <pre className="whitespace-pre-wrap text-sm font-sans">{mutate.data.text}</pre>
        </div>
      )}

      {mutate.error && (
        <div className="bg-red-50 border border-red-200 text-red-800 rounded p-3 text-sm">
          Ошибка расчёта.
        </div>
      )}

      <section className="bg-white rounded-lg shadow p-5 space-y-4">
        <div>
          <h2 className="text-xl font-semibold">Расчёт дроссельной диафрагмы</h2>
          <p className="text-sm text-gray-500">Минимальное значение результата: 3.</p>
        </div>

        <div className="space-y-3">
          <label className="flex items-center gap-3">
            <span className="w-64 text-sm text-gray-700 shrink-0">Перепад давления</span>
            <input
              type="text"
              inputMode="decimal"
              value={diaphragmForm.pressureDrop}
              onChange={(e) => setDiaphragmForm((current) => ({ ...current, pressureDrop: e.target.value }))}
              className="border rounded px-2 py-1 flex-1"
            />
          </label>
          <label className="flex items-center gap-3">
            <span className="w-64 text-sm text-gray-700 shrink-0">Нагрузка на отопление</span>
            <input
              type="text"
              inputMode="decimal"
              value={diaphragmForm.heatingLoad}
              onChange={(e) => setDiaphragmForm((current) => ({ ...current, heatingLoad: e.target.value }))}
              className="border rounded px-2 py-1 flex-1"
            />
          </label>
        </div>

        <div className="flex items-center gap-2 pt-1">
          <div className="rounded border bg-gray-50 px-4 py-2 text-sm">
            Диафрагма:{' '}
            <span className="font-semibold text-gray-900">
              {diaphragmResult === null ? '—' : formatOneDecimal(diaphragmResult.diameter)}
            </span>
          </div>
          <div className="rounded border bg-gray-50 px-4 py-2 text-sm">
            Вариант:{' '}
            <span className="font-semibold text-gray-900">
              {diaphragmResult === null ? '—' : diaphragmResult.washers}
            </span>
          </div>
          <button
            type="button"
            onClick={() => setDiaphragmForm({ pressureDrop: '', heatingLoad: '' })}
            className="bg-white border px-4 py-2 rounded text-sm hover:bg-gray-100"
          >
            Очистить
          </button>
        </div>
      </section>
    </div>
  )
}

function parseDecimal(value: string) {
  const normalized = value.trim().replace(',', '.')
  if (!normalized) return null

  const parsed = Number(normalized)
  return Number.isFinite(parsed) ? parsed : null
}

function diaphragmValue(heatingLoad: number, pressureDrop: number) {
  const raw = 10 * ((((heatingLoad * 1_000_000) / 80_000) ** 2 / pressureDrop) ** (1 / 4))
  return Math.round(raw * 10) / 10
}

function formatOneDecimal(value: number) {
  return value.toLocaleString('ru-RU', { maximumFractionDigits: 1 })
}
