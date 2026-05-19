import { useMutation, useQuery } from '@tanstack/react-query'
import { useState, type FormEvent } from 'react'
import { arshinApi, type ArshinForm, type ArshinItem } from '../../api/arshin'

const FIELDS: { key: keyof ArshinForm; label: string }[] = [
  { key: 'org_title', label: 'Поверитель (организация)' },
  { key: 'year', label: 'Год поверки' },
  { key: 'mi_number', label: 'Номер прибора' },
  { key: 'mit_notation', label: 'Тип/обозн. прибора' },
]

export default function ArshinHome() {
  const [form, setForm] = useState<ArshinForm>({
    org_title: '',
    year: String(new Date().getFullYear()),
    mi_number: '',
    mit_notation: '',
  })
  const [busyPdfFor, setBusyPdfFor] = useState<number | null>(null)

  const opts = useQuery({
    queryKey: ['arshin', 'options'],
    queryFn: () => arshinApi.options(),
  })

  const search = useMutation({
    mutationFn: (f: ArshinForm) => arshinApi.search(f),
  })

  const onSubmit = (e: FormEvent) => {
    e.preventDefault()
    search.mutate(form)
  }

  const onClear = () => {
    setForm({ org_title: '', year: String(new Date().getFullYear()), mi_number: '', mit_notation: '' })
    search.reset()
  }

  const downloadPdf = async (item: ArshinItem, idx: number) => {
    setBusyPdfFor(idx)
    try {
      const blob = await arshinApi.pdfBlob(item)
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      const name = item.mi_number || item.vri_id || 'verification'
      a.download = `Поверка_${name}.pdf`
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) {
      alert(`Не удалось получить PDF: ${(e as Error).message}`)
    } finally {
      setBusyPdfFor(null)
    }
  }

  return (
    <div className="space-y-4 max-w-3xl">
      <h1 className="text-2xl font-bold">🔬 АРШИН — поверка приборов</h1>

      <form onSubmit={onSubmit} className="bg-white rounded-lg shadow p-5 space-y-3">
        {FIELDS.map((f) => (
          <label key={f.key} className="flex items-center gap-3">
            <span className="w-56 text-sm text-gray-700 shrink-0">{f.label}</span>
            {f.key === 'org_title' && opts.data ? (
              <select
                value={form.org_title}
                onChange={(e) => setForm({ ...form, org_title: e.target.value })}
                className="border rounded px-2 py-1 flex-1"
              >
                <option value="">— любая —</option>
                {opts.data.orgs.map((o) => (
                  <option key={o} value={o}>
                    {o}
                  </option>
                ))}
              </select>
            ) : f.key === 'year' && opts.data ? (
              <select
                value={form.year}
                onChange={(e) => setForm({ ...form, year: e.target.value })}
                className="border rounded px-2 py-1 flex-1"
              >
                {opts.data.years.map((y) => (
                  <option key={y} value={y}>
                    {y}
                  </option>
                ))}
              </select>
            ) : (
              <input
                type="text"
                value={form[f.key]}
                onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
                className="border rounded px-2 py-1 flex-1"
              />
            )}
          </label>
        ))}

        <div className="flex gap-2 pt-2">
          <button
            type="submit"
            disabled={search.isPending}
            className="bg-blue-600 text-white px-4 py-1.5 rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {search.isPending ? 'Ищу...' : 'Найти прибор'}
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

      {search.data && (
        <div className="space-y-3">
          <pre className="whitespace-pre-wrap text-sm font-sans bg-white rounded shadow p-4">
            {search.data.text}
          </pre>

          {search.data.items.length > 0 && (
            <div className="space-y-2">
              {search.data.items.map((item, i) => (
                <div key={i} className="bg-white rounded shadow p-4 flex items-start justify-between gap-3">
                  <div className="text-sm">
                    <div className="font-medium">
                      №{i + 1} • {item.mi_number || '—'} • {item.mit_notation || ''}
                    </div>
                    <div className="text-gray-600">
                      Поверка: {item.verification_date || '—'} · до {item.valid_date || '—'}
                    </div>
                    <div className="text-gray-600">{item.org_title || ''}</div>
                  </div>
                  <button
                    onClick={() => downloadPdf(item, i)}
                    disabled={busyPdfFor === i}
                    className="bg-green-600 text-white px-3 py-1 rounded hover:bg-green-700 disabled:opacity-50 whitespace-nowrap"
                  >
                    {busyPdfFor === i ? '⏳' : '📄 PDF'}
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
