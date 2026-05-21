import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { meteringApi, type CreateMeteringPayload, type MeteringCompareIdentifiersResult } from '../../api/metering'
import { objectsApi, type ObjectRecord } from '../../api/objects'
import { useAuth } from '../../contexts/AuthContext'
import { meteringFieldLabel } from './meteringFieldLabels'

const CATEGORY_LABELS: Record<string, string> = {
  gspo: 'ГСПО',
  phys: 'Прочие ФЛ',
  legal: 'Прочие ЮЛ',
  budget: 'Бюджет',
  iglakovo: 'Иглаково (коттеджи)',
  embedded: 'Встроенные помещения',
  bu2: 'БУ-2',
  uk_tsj: 'УК и ТСЖ',
}

type FlowmeterBlock = { type: string; serial: string; verificationDate: string }
type TempSensorBlock = { serial: string; verificationDate: string }
type PressureSensorBlock = { serial: string; verificationDate: string }

const emptyFlowmeter = (): FlowmeterBlock => ({ type: '', serial: '', verificationDate: '' })
const emptyTempSensor = (): TempSensorBlock => ({ serial: '', verificationDate: '' })
const emptyPressureSensor = (): PressureSensorBlock => ({ serial: '', verificationDate: '' })

export default function MeteringList() {
  const { category } = useParams<{ category: string }>()
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  const [query, setQuery] = useState(searchParams.get('q') ?? '')
  const [showCreate, setShowCreate] = useState(false)
  const [message, setMessage] = useState('')
  const [importDetailsOpen, setImportDetailsOpen] = useState(false)
  const [importDetails, setImportDetails] = useState<Array<{ id: number; source_row: number; name: string | null; address: string | null; identifier: string | null; changed_fields: string[]; changes?: Record<string, { before: string; after: string }> }>>([])
  const [compareOpen, setCompareOpen] = useState(false)
  const [compareResult, setCompareResult] = useState<MeteringCompareIdentifiersResult | null>(null)
  const page = Number(searchParams.get('page') ?? 0)
  const queryClient = useQueryClient()
  const { user } = useAuth()

  const cat = category ?? 'gspo'
  const label = CATEGORY_LABELS[cat] || cat

  const { data, isLoading, error, isFetching } = useQuery({
    queryKey: ['metering', cat, page, query.trim()],
    queryFn: () => meteringApi.list(cat, page, query),
    placeholderData: (previousData) => previousData,
  })

  const compareMutation = useMutation({
    mutationFn: (file: File) => meteringApi.compareIdentifiers(cat, file),
    onSuccess: (result) => {
      setCompareResult(result)
      setCompareOpen(true)
      setMessage(
        `Сверка: совпало ${result.matched_count}, только в файле ${result.in_file_only.length}, только в БД ${result.in_db_only.length}, дубликаты ${result.duplicates_in_file.length}.`,
      )
    },
    onError: (err: { message?: string }) => setMessage(err.message || 'Не удалось сверить идентификаторы.'),
  })

  const importMutation = useMutation({
    mutationFn: (file: File) => meteringApi.importMetering(cat, file),
    onSuccess: async (result) => {
      const unchanged = result.unchanged ?? 0
      let msg = `Актуализация: создано ${result.added}, обновлено ${result.updated}, без изменений ${unchanged}, пропущено ${result.skipped}.`
      if (result.warnings?.length) msg += ` Предупреждения: ${result.warnings.length}.`
      setMessage(msg)
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

  const exportUrl = `/api/metering/${cat}/export`

  return (
    <div className="space-y-4">
      <nav className="text-sm"><Link to="/metering" className="text-blue-600 hover:underline">← Приборы учета</Link></nav>
      <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h1 className="text-2xl font-bold">{label}</h1>
          <p className="text-sm text-gray-600">{data ? `Всего объектов: ${data.total}` : 'Объекты УУТЭ'}{isFetching ? ' · обновляю...' : ''}</p>
          {data?.last_import && <p className="text-xs text-gray-500">Последний импорт: {new Date(data.last_import.imported_at * 1000).toLocaleString('ru-RU')}</p>}
        </div>
        <div className="flex flex-col gap-2 sm:flex-row">
          <input type="search" value={query} onChange={(event) => onQueryChange(event.target.value)} placeholder="Поиск по названию, адресу, договору, прибору..." className="w-full rounded border bg-white px-3 py-2 text-sm sm:w-96" />
          <a href={exportUrl} className="inline-flex items-center justify-center rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100">Выгрузить объекты</a>
          {(user?.role === 'admin' || user?.role === 'full') && (
            <>
              <button type="button" onClick={() => setShowCreate(true)} className="inline-flex items-center justify-center rounded bg-blue-600 px-3 py-2 text-sm text-white hover:bg-blue-700">+ Создать прибор</button>
              <label className="inline-flex cursor-pointer items-center justify-center rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100">
                {compareMutation.isPending ? 'Сверка...' : 'Сверить идентификаторы'}
                <input type="file" accept=".xls,.xlsx" className="hidden" disabled={compareMutation.isPending || importMutation.isPending} onChange={(event) => { const file = event.target.files?.[0]; if (file) compareMutation.mutate(file); event.currentTarget.value = '' }} />
              </label>
              <label className="inline-flex cursor-pointer items-center justify-center rounded border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-800 hover:bg-blue-100">
                {importMutation.isPending ? 'Актуализация...' : 'Актуализировать из Excel'}
                <input type="file" accept=".xls,.xlsx" className="hidden" disabled={compareMutation.isPending || importMutation.isPending} onChange={(event) => { const file = event.target.files?.[0]; if (file) importMutation.mutate(file); event.currentTarget.value = '' }} />
              </label>
            </>
          )}
        </div>
      </div>

      {message && (
        <div className="rounded border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span>{message}</span>
            {importDetails.length > 0 && <button type="button" onClick={() => setImportDetailsOpen(true)} className="rounded border border-blue-300 bg-white px-2 py-1 text-xs text-blue-700 hover:bg-blue-50">Показать изменения</button>}
          </div>
        </div>
      )}

      {compareOpen && compareResult && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-3xl rounded-lg bg-white p-4 shadow-xl">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-base font-semibold text-gray-900">Сверка идентификаторов</h2>
              <button type="button" onClick={() => setCompareOpen(false)} className="rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100">Закрыть</button>
            </div>
            <p className="mb-3 text-sm text-gray-700">
              Совпало {compareResult.matched_count}, только в Excel {compareResult.in_file_only.length}, только в БД {compareResult.in_db_only.length}, дубликаты {compareResult.duplicates_in_file.length}.
            </p>
            <div className="grid gap-3 sm:grid-cols-3 max-h-[50vh] overflow-auto text-xs">
              <div>
                <h3 className="font-medium mb-1">Только в Excel</h3>
                {compareResult.in_file_only.length > 0 && <p className="mb-1 text-gray-500">При актуализации эти строки не изменяются.</p>}
                <ul className="text-gray-700">{compareResult.in_file_only.length === 0 ? <li>—</li> : compareResult.in_file_only.map((id) => <li key={id}>{id}</li>)}</ul>
              </div>
              <div>
                <h3 className="font-medium mb-1">Только в БД</h3>
                <ul className="text-gray-700">{compareResult.in_db_only.length === 0 ? <li>—</li> : compareResult.in_db_only.map((id) => <li key={id}>{id}</li>)}</ul>
              </div>
              <div>
                <h3 className="font-medium mb-1">Дубликаты в файле</h3>
                <ul className="text-gray-700">{compareResult.duplicates_in_file.length === 0 ? <li>—</li> : compareResult.duplicates_in_file.map((id) => <li key={id}>{id}</li>)}</ul>
              </div>
            </div>
          </div>
        </div>
      )}

      {importDetailsOpen && importDetails.length > 0 && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-5xl rounded-lg bg-white p-4 shadow-xl">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-base font-semibold text-gray-900">Что изменилось</h2>
              <button type="button" onClick={() => setImportDetailsOpen(false)} className="rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100">Закрыть</button>
            </div>
            <div className="max-h-[70vh] overflow-auto rounded border border-gray-200">
              <table className="min-w-full text-left text-xs text-gray-800">
                <thead className="bg-gray-50"><tr><th className="px-2 py-1">Строка</th><th className="px-2 py-1">Объект</th><th className="px-2 py-1">Изменения</th></tr></thead>
                <tbody>
                  {importDetails.map((row, index) => (
                    <tr key={`${row.id}-${index}`} className="border-t">
                      <td className="px-2 py-1">{row.source_row}</td>
                      <td className="px-2 py-1"><Link to={`/metering/${cat}/${row.id}`} className="text-blue-700 hover:underline">{row.name || row.address || row.identifier || `#${row.id}`}</Link></td>
                      <td className="px-2 py-1">
                        {row.changed_fields.length === 0 && '—'}
                        {row.changed_fields.map((field) => {
                          const change = row.changes?.[field]
                          const fLabel = meteringFieldLabel(field)
                          if (!change) return <div key={field}>{fLabel}</div>
                          const before = change.before?.trim() ? change.before : '—'
                          const after = change.after?.trim() ? change.after : '—'
                          return <div key={field}>{fLabel}: {before} → {after}</div>
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
      {data && data.records.length === 0 && <p className="rounded bg-white p-4 shadow text-gray-500">Ничего не найдено.</p>}

      {data && data.records.length > 0 && (
        <div className="overflow-x-auto rounded-lg bg-white shadow">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-100 text-left"><tr><th className="px-3 py-2 w-14">#</th><th className="px-3 py-2">Название</th><th className="px-3 py-2">Адрес</th><th className="px-3 py-2">Вычислитель</th><th className="px-3 py-2">Ближайшая поверка</th></tr></thead>
            <tbody>
              {data.records.map((record, index) => (
                <tr key={record.id} className="border-t hover:bg-gray-50">
                  <td className="px-3 py-2 text-gray-500">{data.page * data.page_size + index + 1}</td>
                  <td className="px-3 py-2 max-w-80"><Link to={`/metering/${cat}/${record.id}`} className="block break-words text-blue-700 hover:underline">{record.name || '—'}</Link></td>
                  <td className="px-3 py-2 text-gray-700">{record.address || '—'}</td>
                  <td className="px-3 py-2">{[record.calculator_type, record.calculator_serial].filter(Boolean).join(' # ') || '—'}</td>
                  <td className="px-3 py-2">{record.nearest_verification_date || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {data && pageCount > 1 && (
        <div className="flex items-center justify-between">
          <button type="button" disabled={page === 0} onClick={() => setPage(page - 1)} className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100">← Назад</button>
          <span className="text-sm text-gray-600">Страница {page + 1} из {pageCount}</span>
          <button type="button" disabled={page >= pageCount - 1} onClick={() => setPage(page + 1)} className="rounded border bg-white px-3 py-1.5 text-sm disabled:opacity-40 hover:bg-gray-100">Далее →</button>
        </div>
      )}

      {showCreate && (
        <CreateMeteringModal
          category={cat}
          onClose={() => setShowCreate(false)}
          onCreated={(id) => navigate(`/metering/${cat}/${id}`)}
        />
      )}
    </div>
  )
}

function CreateMeteringModal({ category: initialCat, onClose, onCreated }: { category: string; onClose: () => void; onCreated: (id: number) => void }) {
  const [cat, setCat] = useState(initialCat)
  const [objectSearch, setObjectSearch] = useState('')
  const [selectedObject, setSelectedObject] = useState<ObjectRecord | null>(null)
  const [objectCandidates, setObjectCandidates] = useState<ObjectRecord[]>([])
  const [calculatorType, setCalculatorType] = useState('')
  const [calculatorSerial, setCalculatorSerial] = useState('')
  const [calculatorVerification, setCalculatorVerification] = useState('')
  const [flowmeters, setFlowmeters] = useState<FlowmeterBlock[]>([emptyFlowmeter()])
  const [tempSensors, setTempSensors] = useState<TempSensorBlock[]>([emptyTempSensor()])
  const [pressureSensors, setPressureSensors] = useState<PressureSensorBlock[]>([emptyPressureSensor()])
  const createMutation = useMutation({
    mutationFn: () => {
      const payload: CreateMeteringPayload = { object_id: selectedObject!.id }
      if (calculatorType) payload.calculator_type = calculatorType
      if (calculatorSerial) payload.calculator_serial = calculatorSerial
      if (calculatorVerification) payload.calculator_verification_date = calculatorVerification
      flowmeters.forEach((fm, i) => {
        const idx = i + 1
        if (idx > 4) return
        if (fm.type) (payload as any)[`flowmeter_${idx}`] = fm.type
        if (fm.serial) (payload as any)[`flowmeter_serial_${idx}`] = fm.serial
        if (fm.verificationDate) (payload as any)[`flowmeter_verification_date_${idx}`] = fm.verificationDate
      })
      tempSensors.forEach((ts, i) => {
        const idx = i + 1
        if (idx > 4) return
        if (ts.serial) (payload as any)[`temp_sensor_serial_${idx}`] = ts.serial
        if (ts.verificationDate) (payload as any)[`temp_sensor_verification_date_${idx}`] = ts.verificationDate
      })
      pressureSensors.forEach((ps, i) => {
        const idx = i + 1
        if (idx > 4) return
        if (ps.serial) (payload as any)[`pressure_sensor_serial_${idx}`] = ps.serial
        if (ps.verificationDate) (payload as any)[`pressure_sensor_verification_date_${idx}`] = ps.verificationDate
      })
      return meteringApi.create(cat, payload)
    },
    onSuccess: (record) => onCreated(record.id),
  })

  const searchObjects = () => {
    const q = objectSearch.trim()
    if (!q || q.length < 1) return
    objectsApi.list(cat, q).then((res) => setObjectCandidates(res.records))
  }

  return (
    <div className="fixed inset-0 z-40 flex items-start justify-center bg-black/40 p-4 pt-12 overflow-y-auto">
      <div className="w-full max-w-2xl rounded-lg bg-white p-5 shadow-xl">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold">Создать прибор учета</h2>
          <button type="button" onClick={onClose} className="rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100">Закрыть</button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Категория</label>
            <select value={cat} onChange={(e) => setCat(e.target.value)} className="w-full rounded border px-3 py-2 text-sm">
              {Object.entries(CATEGORY_LABELS).map(([key, lbl]) => (
                <option key={key} value={key}>{lbl}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Объект (registry_object) *</label>
            <div className="flex gap-2">
              <input value={objectSearch} onChange={(e) => setObjectSearch(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') searchObjects() }} placeholder="Поиск по имени или адресу..." className="flex-1 rounded border px-3 py-2 text-sm" />
              <button type="button" onClick={searchObjects} className="rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100">Найти</button>
            </div>
            {objectCandidates.length > 0 && (
              <div className="mt-2 max-h-40 overflow-y-auto rounded border text-sm">
                {objectCandidates.map((obj) => (
                  <button
                    key={obj.id}
                    type="button"
                    onClick={() => { setSelectedObject(obj); setObjectCandidates([]); setObjectSearch(`${obj.name || ''} — ${obj.address || ''}`) }}
                    className={`block w-full px-3 py-2 text-left hover:bg-blue-50 ${selectedObject?.id === obj.id ? 'bg-blue-100' : ''}`}
                  >
                    <span className="font-medium">{obj.name || '—'}</span>
                    <span className="text-gray-500 ml-2">{obj.address || '—'}</span>
                  </button>
                ))}
              </div>
            )}
            {selectedObject && !objectCandidates.length && (
              <p className="mt-1 text-xs text-green-700">Выбран: {selectedObject.name || '—'} — {selectedObject.address || '—'}</p>
            )}
          </div>

          <fieldset className="rounded border p-3">
            <legend className="text-sm font-medium text-gray-700 px-1">Вычислитель</legend>
            <div className="grid gap-3 sm:grid-cols-3">
              <input value={calculatorType} onChange={(e) => setCalculatorType(e.target.value)} placeholder="Тип" className="rounded border px-3 py-2 text-sm" />
              <input value={calculatorSerial} onChange={(e) => setCalculatorSerial(e.target.value)} placeholder="Серийный номер" className="rounded border px-3 py-2 text-sm" />
              <input value={calculatorVerification} onChange={(e) => setCalculatorVerification(e.target.value)} type="date" className="rounded border px-3 py-2 text-sm" />
            </div>
          </fieldset>

          <SensorBlockGroup
            title="Расходомеры"
            items={flowmeters}
            maxItems={4}
            hasType
            onAdd={() => setFlowmeters((c) => [...c, emptyFlowmeter()])}
            onChange={(i, field, val) => setFlowmeters((c) => { const n = [...c]; n[i] = { ...n[i], [field]: val }; return n })}
            onRemove={(i) => setFlowmeters((c) => c.filter((_, idx) => idx !== i))}
          />

          <SensorBlockGroup
            title="Термометры"
            items={tempSensors}
            maxItems={4}
            hasType={false}
            onAdd={() => setTempSensors((c) => [...c, emptyTempSensor()])}
            onChange={(i, field, val) => setTempSensors((c) => { const n = [...c]; n[i] = { ...n[i], [field]: val }; return n })}
            onRemove={(i) => setTempSensors((c) => c.filter((_, idx) => idx !== i))}
          />

          <SensorBlockGroup
            title="Датчики давления"
            items={pressureSensors}
            maxItems={4}
            hasType={false}
            onAdd={() => setPressureSensors((c) => [...c, emptyPressureSensor()])}
            onChange={(i, field, val) => setPressureSensors((c) => { const n = [...c]; n[i] = { ...n[i], [field]: val }; return n })}
            onRemove={(i) => setPressureSensors((c) => c.filter((_, idx) => idx !== i))}
          />
        </div>

        <div className="mt-6 flex items-center justify-end gap-3">
          <button type="button" onClick={onClose} className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Отмена</button>
          <button
            type="button"
            disabled={!selectedObject || createMutation.isPending}
            onClick={() => createMutation.mutate()}
            className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
          >
            {createMutation.isPending ? 'Создание...' : 'Создать'}
          </button>
        </div>
        {createMutation.error && (
          <div className="mt-3 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            {(createMutation.error as { message?: string }).message || 'Ошибка создания.'}
          </div>
        )}
      </div>
    </div>
  )
}

function SensorBlockGroup({ title, items, maxItems, hasType, onAdd, onChange, onRemove }: {
  title: string
  items: Array<Record<string, string>>
  maxItems: number
  hasType: boolean
  onAdd: () => void
  onChange: (index: number, field: string, value: string) => void
  onRemove: (index: number) => void
}) {
  return (
    <fieldset className="rounded border p-3">
      <legend className="text-sm font-medium text-gray-700 px-1">{title}</legend>
      <div className="space-y-2">
        {items.map((item, i) => (
          <div key={i} className="flex items-end gap-2">
            {hasType && (
              <input value={item.type || ''} onChange={(e) => onChange(i, 'type', e.target.value)} placeholder="Тип" className="flex-1 rounded border px-3 py-2 text-sm" />
            )}
            <input value={item.serial || ''} onChange={(e) => onChange(i, 'serial', e.target.value)} placeholder="Серийный номер" className="flex-1 rounded border px-3 py-2 text-sm" />
            <input value={item.verificationDate || ''} onChange={(e) => onChange(i, 'verificationDate', e.target.value)} type="date" className="w-40 rounded border px-3 py-2 text-sm" />
            {items.length > 1 && (
              <button type="button" onClick={() => onRemove(i)} className="shrink-0 rounded border border-red-200 bg-white px-2 py-2 text-sm text-red-600 hover:bg-red-50">×</button>
            )}
          </div>
        ))}
        {items.length < maxItems && (
          <button type="button" onClick={onAdd} className="text-sm text-blue-600 hover:underline">+ Добавить</button>
        )}
      </div>
    </fieldset>
  )
}
