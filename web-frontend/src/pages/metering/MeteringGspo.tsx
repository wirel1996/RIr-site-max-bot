import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { meteringApi } from '../../api/metering'
import { useAuth } from '../../contexts/AuthContext'
import { meteringFieldLabel } from './meteringFieldLabels'

export default function MeteringGspo() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [query, setQuery] = useState(searchParams.get('q') ?? '')
  const [message, setMessage] = useState('')
  const [importDetailsOpen, setImportDetailsOpen] = useState(false)
  const [importDetails, setImportDetails] = useState<Array<{
    id: number
    source_row: number
    name: string | null
    address: string | null
    identifier: string | null
    changed_fields: string[]
    changes?: Record<string, { before: string; after: string }>
  }>>([])
  const page = Number(searchParams.get('page') ?? 0)
  const queryClient = useQueryClient()
  const { user } = useAuth()

  const { data, isLoading, error, isFetching } = useQuery({
    queryKey: ['metering', 'gspo', page, query.trim()],
    queryFn: () => meteringApi.listGspo(page, query),
    placeholderData: (previousData) => previousData,
  })

  const importMutation = useMutation({
    mutationFn: (file: File) => meteringApi.importGspo(file),
    onSuccess: async (result) => {
      const unchanged = result.unchanged ?? 0
      setMessage(`Импорт: добавлено ${result.added}, изменено ${result.updated}, без изменений ${unchanged}, пропущено ${result.skipped}.`)
      setImportDetails(result.updated_examples ?? [])
      setImportDetailsOpen((result.updated_examples ?? []).length > 0)
      await queryClient.invalidateQueries({ queryKey: ['metering'] })
    },
    onError: (err: { message?: string }) => setMessage(err.message || 'Не удалось импортировать файл.'),
  })

  const pageCount = data ? Math.max(Math.ceil(data.total / data.page_size), 1) : 1

  const setPage = (nextPage: number) => {
    const params = new URLSearchParams()
    if (query.trim()) params.set('q', query.trim())
    if (nextPage > 0) params.set('page', String(nextPage))
    setSearchParams(params)
  }

  const onQueryChange = (value: string) => {
    setQuery(value)
    const params = new URLSearchParams()
    if (value.trim()) params.set('q', value.trim())
    setSearchParams(params)
  }

  return (
    <div className="space-y-4">
      <nav className="text-sm">
        <Link to="/metering" className="text-blue-600 hover:underline">
          ← Приборы учета
        </Link>
      </nav>

      <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h1 className="text-2xl font-bold">ГСПО</h1>
          <p className="text-sm text-gray-600">
            {data ? `Всего объектов: ${data.total}` : 'Объекты УУТЭ'}
            {isFetching ? ' · обновление...' : ''}
          </p>
          {data?.last_import && (
            <p className="text-xs text-gray-500">
              Последний импорт: {new Date(data.last_import.imported_at * 1000).toLocaleString('ru-RU')}
            </p>
          )}
        </div>

          <div className="flex flex-col gap-2 sm:flex-row">
          <input
            type="search"
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder="Поиск по названию, адресу, договору, прибору..."
            className="w-full rounded border bg-white px-3 py-2 text-sm sm:w-96"
          />
          <a
            href={meteringApi.gspoExportUrl()}
            className="inline-flex items-center justify-center rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
          >
            Выгрузить объекты
          </a>
          {(user?.role === 'admin' || user?.role === 'full') && (
            <label className="inline-flex cursor-pointer items-center justify-center rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100">
              {importMutation.isPending ? 'Загрузка...' : 'Загрузить Excel'}
              <input
                type="file"
                accept=".xls,.xlsx"
                className="hidden"
                disabled={importMutation.isPending}
                onChange={(event) => {
                  const file = event.target.files?.[0]
                  if (file) importMutation.mutate(file)
                  event.currentTarget.value = ''
                }}
              />
            </label>
          )}
        </div>
      </div>

      {message && (
        <div className="rounded border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span>{message}</span>
            {importDetails.length > 0 && (
              <button
                type="button"
                onClick={() => setImportDetailsOpen(true)}
                className="rounded border border-blue-300 bg-white px-2 py-1 text-xs text-blue-700 hover:bg-blue-50"
              >
                Посмотреть изменения
              </button>
            )}
          </div>
        </div>
      )}
      {importDetailsOpen && importDetails.length > 0 && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-5xl rounded-lg bg-white p-4 shadow-xl">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-base font-semibold text-gray-900">Что изменилось</h2>
              <button
                type="button"
                onClick={() => setImportDetailsOpen(false)}
                className="rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100"
              >
                Закрыть
              </button>
            </div>
            <div className="max-h-[70vh] overflow-auto rounded border border-gray-200">
              <table className="min-w-full text-left text-xs text-gray-800">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-2 py-1">Строка</th>
                    <th className="px-2 py-1">Объект</th>
                    <th className="px-2 py-1">Что изменилось</th>
                  </tr>
                </thead>
                <tbody>
                  {importDetails.map((row, index) => (
                    <tr key={`${row.id}-${index}`} className="border-t">
                      <td className="px-2 py-1">{row.source_row}</td>
                      <td className="px-2 py-1">
                        <Link to={`/metering/gspo/${row.id}`} className="text-blue-700 hover:underline">
                          {row.name || row.address || row.identifier || `#${row.id}`}
                        </Link>
                      </td>
                      <td className="px-2 py-1">
                        {row.changed_fields.length === 0 && '—'}
                        {row.changed_fields.map((field) => {
                          const change = row.changes?.[field]
                          const label = meteringFieldLabel(field)
                          if (!change) return <div key={field}>{label}</div>
                          const before = change.before?.trim() ? change.before : '—'
                          const after = change.after?.trim() ? change.after : '—'
                          return <div key={field}>{label}: {before} → {after}</div>
                        })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}
      {isLoading && <div className="text-gray-500">Загрузка...</div>}
      {error && <div className="rounded border border-red-200 bg-red-50 p-3 text-red-800">Ошибка загрузки.</div>}

      {data && data.records.length === 0 && (
        <p className="rounded bg-white p-4 shadow text-gray-500">Ничего не найдено.</p>
      )}

      {data && data.records.length > 0 && (
        <div className="overflow-x-auto rounded-lg bg-white shadow">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-100 text-left">
              <tr>
                <th className="px-3 py-2 w-14">#</th>
                <th className="px-3 py-2">Наименование</th>
                <th className="px-3 py-2">Адрес</th>
                <th className="px-3 py-2">Тепловычислитель</th>
                <th className="px-3 py-2">Ближайшая поверка</th>
              </tr>
            </thead>
            <tbody>
              {data.records.map((record, index) => (
                <tr key={record.id} className="border-t hover:bg-gray-50">
                  <td className="px-3 py-2 text-gray-500">{data.page * data.page_size + index + 1}</td>
                  <td className="px-3 py-2 max-w-80">
                    <Link to={`/metering/gspo/${record.id}`} className="block break-words text-blue-700 hover:underline">
                      {record.name || '—'}
                    </Link>
                  </td>
                  <td className="px-3 py-2 text-gray-700">{record.address || '—'}</td>
                  <td className="px-3 py-2">{[record.calculator_type, record.calculator_serial].filter(Boolean).join(' № ') || '—'}</td>
                  <td className="px-3 py-2">{record.nearest_verification_date || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {data && pageCount > 1 && (
        <div className="flex items-center justify-between">
          <button
            type="button"
            disabled={page === 0}
            onClick={() => setPage(page - 1)}
            className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100"
          >
            ← Пред.
          </button>
          <span className="text-sm text-gray-600">Страница {page + 1} из {pageCount}</span>
          <button
            type="button"
            disabled={page >= pageCount - 1}
            onClick={() => setPage(page + 1)}
            className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100"
          >
            След. →
          </button>
        </div>
      )}
    </div>
  )
}
