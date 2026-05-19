import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link, useSearchParams } from 'react-router-dom'
import { useState } from 'react'
import { billingApi, type BillingStatusFilter } from '../../api/billing'

const PAGE_SIZE = 50

export default function BillingHome() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [query, setQuery] = useState(searchParams.get('q') ?? '')
  const page = Number(searchParams.get('page') ?? 0)
  const status = (searchParams.get('status') as BillingStatusFilter) || 'active'
  const qc = useQueryClient()
  const [menuOpen, setMenuOpen] = useState(false)
  const [actionError, setActionError] = useState('')

  const { data, isLoading, error, isFetching } = useQuery({
    queryKey: ['billing', 'objects', page, query.trim(), status],
    queryFn: () => billingApi.list(page, query, PAGE_SIZE, status),
    placeholderData: (previousData) => previousData,
  })
  const sheetsQuery = useQuery({
    queryKey: ['billing', 'sheets'],
    queryFn: () => billingApi.sheets(),
  })

  const createMutation = useMutation({
    mutationFn: () => billingApi.createObject({ status: 'активный', contract_name: 'New object' }),
    onSuccess: (created) => {
      setActionError('')
      qc.invalidateQueries({ queryKey: ['billing', 'objects'] })
      window.location.href = `/billing/${created.row}`
    },
    onError: (e: { message?: string }) => {
      setActionError(e.message || 'Не удалось создать карточку')
    },
  })
  const nextMonthMutation = useMutation({
    mutationFn: () => billingApi.createNextMonth(),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: ['billing', 'sheets'] })
      await qc.invalidateQueries({ queryKey: ['billing', 'objects'] })
    },
  })
  const deleteMonthMutation = useMutation({
    mutationFn: (sheetId: number) => billingApi.deleteSheet(sheetId),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: ['billing', 'sheets'] })
      await qc.invalidateQueries({ queryKey: ['billing', 'objects'] })
    },
  })
  const setCurrentSheetMutation = useMutation({
    mutationFn: (sheetId: number) => billingApi.setCurrentSheet(sheetId),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: ['billing', 'sheets'] })
      await qc.invalidateQueries({ queryKey: ['billing', 'objects'] })
      setSearchParams((prev) => {
        const p = new URLSearchParams(prev)
        p.delete('page')
        return p
      })
    },
  })

  const pageCount = data ? Math.max(Math.ceil(data.total / data.page_size), 1) : 1
  const currentSheet = sheetsQuery.data?.sheets.find((s) => s.current)

  const setParams = (next: { q?: string; page?: number; status?: BillingStatusFilter }) => {
    const params = new URLSearchParams()
    const q = next.q ?? query
    const p = next.page ?? 0
    const st = next.status ?? status
    if (q.trim()) params.set('q', q.trim())
    if (p > 0) params.set('page', String(p))
    if (st !== 'active') params.set('status', st)
    setSearchParams(params)
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold">ГВС биллинг</h1>
          <p className="text-sm text-gray-600">
            {data?.sheet ? `Лист: ${data.sheet}` : 'Текущий лист'}
            {data ? ` · records: ${data.total}` : ''}
            {isFetching ? ' · обновление...' : ''}
          </p>
        </div>
        <div className="flex gap-2 items-center flex-wrap">
          <select
            className="rounded border bg-white px-3 py-2 text-sm"
            value={currentSheet?.id || ''}
            onChange={(e) => setCurrentSheetMutation.mutate(Number(e.target.value))}
          >
            {(sheetsQuery.data?.sheets || []).map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
          <div className="inline-flex rounded border bg-white text-sm overflow-hidden">
            <button type="button" onClick={() => setParams({ status: 'active', page: 0 })} className={`px-3 py-2 ${status === 'active' ? 'bg-blue-600 text-white' : 'hover:bg-gray-100'}`}>Активные</button>
            <button type="button" onClick={() => setParams({ status: 'all', page: 0 })} className={`px-3 py-2 border-l ${status === 'all' ? 'bg-blue-600 text-white' : 'hover:bg-gray-100'}`}>Все</button>
            <button type="button" onClick={() => setParams({ status: 'inactive', page: 0 })} className={`px-3 py-2 border-l ${status === 'inactive' ? 'bg-blue-600 text-white' : 'hover:bg-gray-100'}`}>Неактивные</button>
          </div>
          <div className="relative">
            <button className="rounded border bg-white px-3 py-2 text-sm hover:bg-gray-100" onClick={() => setMenuOpen((v) => !v)}>Меню</button>
            {menuOpen && (
              <div className="absolute right-0 z-20 mt-1 w-64 rounded border bg-white shadow">
                <button className="w-full text-left px-3 py-2 text-sm hover:bg-gray-100" onClick={() => createMutation.mutate()}>Новая карточка</button>
                <button
                  className="w-full text-left px-3 py-2 text-sm hover:bg-gray-100 disabled:opacity-50"
                  disabled={nextMonthMutation.isPending}
                  onClick={() => {
                    if (window.confirm('Создать следующий месяц?')) {
                      nextMonthMutation.mutate()
                    }
                  }}
                >
                  {nextMonthMutation.isPending ? 'Создание месяца...' : 'Создать след. месяц'}
                </button>
                <button
                  className="w-full text-left px-3 py-2 text-sm text-red-700 hover:bg-red-50"
                  onClick={() => {
                    if (!currentSheet) return
                    if (window.confirm(`Удалить месяц "${currentSheet.name}"?`)) {
                      deleteMonthMutation.mutate(currentSheet.id)
                    }
                  }}
                >
                  Удалить текущий месяц
                </button>
                <a className="block px-3 py-2 text-sm hover:bg-gray-100" href={`/api/billing/export?status=${status}`}>Экспорт</a>
              </div>
            )}
          </div>
          <input
            type="search"
            placeholder="Поиск по имени или адресу..."
            value={query}
            onChange={(e) => {
              setQuery(e.target.value)
              setParams({ q: e.target.value, page: 0 })
            }}
            className="w-full rounded border bg-white px-3 py-2 text-sm sm:w-72"
          />
        </div>
      </div>

      {isLoading && <div className="text-gray-500">Загрузка...</div>}
      {error && <div className="rounded border border-red-200 bg-red-50 p-3 text-red-800">Ошибка загрузки биллинга.</div>}
      {actionError && <div className="rounded border border-red-200 bg-red-50 p-3 text-red-800">{actionError}</div>}

      {data && data.records.length > 0 && (
        <div className="rounded-lg bg-white shadow overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-100">
              <tr>
                <th className="px-3 py-2 text-left w-16">#</th>
                <th className="px-3 py-2 text-left">Статус</th>
                <th className="px-3 py-2 text-left">Наименование</th>
                <th className="px-3 py-2 text-left">Адрес</th>
                <th className="px-3 py-2 text-left">Назначение</th>
                <th className="px-3 py-2 text-left">След. поверка</th>
                <th className="px-3 py-2 text-left">Текущее</th>
                <th className="px-3 py-2 text-left">V ГВС</th>
                <th className="px-3 py-2 w-12"></th>
              </tr>
            </thead>
            <tbody>
              {data.records.map((record, index) => (
                <tr key={record.row} className="border-t hover:bg-gray-50">
                  <td className="px-3 py-2 text-gray-500">{page * data.page_size + index + 1}</td>
                  <td className="px-3 py-2">{record.status || '—'}</td>
                  <td className="px-3 py-2 max-w-72"><Link to={`/billing/${record.row}`} className="text-blue-700 hover:underline">{record.name || '—'}</Link></td>
                  <td className="px-3 py-2">{record.address || '—'}</td>
                  <td className="px-3 py-2">{record.purpose || '—'}</td>
                  <td className="px-3 py-2">{record.poverka_next || '—'}</td>
                  <td className="px-3 py-2">{record.current_value || '—'}</td>
                  <td className="px-3 py-2">{record.volume_gvs || '—'}</td>
                  <td className="px-3 py-2 text-right"><Link to={`/billing/${record.row}`} className="text-blue-600">→</Link></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {data && pageCount > 1 && (
        <div className="flex items-center justify-between">
          <button type="button" disabled={page === 0} onClick={() => setParams({ page: page - 1 })} className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100">← Назад</button>
          <span className="text-sm text-gray-600">Страница {page + 1} из {pageCount}</span>
          <button type="button" disabled={page >= pageCount - 1} onClick={() => setParams({ page: page + 1 })} className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100">Вперёд →</button>
        </div>
      )}
    </div>
  )
}
