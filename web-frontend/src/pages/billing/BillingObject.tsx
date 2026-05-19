import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link, useParams } from 'react-router-dom'
import { useEffect, useState, type FormEvent } from 'react'
import { billingApi, type BillingObject } from '../../api/billing'

function todayRu(): string {
  const d = new Date()
  return `${String(d.getDate()).padStart(2, '0')}.${String(d.getMonth() + 1).padStart(2, '0')}.${d.getFullYear()}`
}

export default function BillingObjectPage() {
  const { row } = useParams<{ row: string }>()
  const rowNum = Number(row)
  const qc = useQueryClient()

  const [editMode, setEditMode] = useState(false)
  const [readingMode, setReadingMode] = useState(false)
  const [readingValue, setReadingValue] = useState('')
  const [form, setForm] = useState<Partial<BillingObject>>({})

  const { data, isLoading, error } = useQuery({
    queryKey: ['billing', 'object', rowNum],
    queryFn: () => billingApi.object(rowNum),
    enabled: rowNum > 0,
  })

  useEffect(() => {
    if (data) setForm(data)
  }, [data])

  const saveCard = useMutation({
    mutationFn: () => billingApi.updateObject(rowNum, form),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['billing', 'object', rowNum] })
      qc.invalidateQueries({ queryKey: ['billing', 'objects'] })
      setEditMode(false)
    },
  })

  const saveReading = useMutation({
    mutationFn: () => billingApi.saveReading(rowNum, readingValue.trim(), todayRu()),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['billing', 'object', rowNum] })
      qc.invalidateQueries({ queryKey: ['billing', 'objects'] })
      setReadingMode(false)
      setReadingValue('')
    },
  })

  if (isLoading) return <div className="text-gray-500">Загрузка...</div>
  if (error || !data) return <div className="text-red-700">Не найдено</div>

  const renderInput = (k: keyof BillingObject, label: string) => (
    <label className="flex flex-col">
      <span className="text-xs text-gray-500">{label}</span>
      <input
        className="rounded border px-2 py-1 text-sm"
        value={(form[k] as string) || ''}
        onChange={(e) => setForm((prev) => ({ ...prev, [k]: e.target.value }))}
      />
    </label>
  )

  const viewRow = (label: string, value?: string) => (
    <div>
      <dt className="text-gray-500">{label}</dt>
      <dd>{value?.trim() ? value : '—'}</dd>
    </div>
  )

  const onSaveCard = (e: FormEvent) => {
    e.preventDefault()
    saveCard.mutate()
  }

  const onSaveReading = (e: FormEvent) => {
    e.preventDefault()
    if (!readingValue.trim()) return
    saveReading.mutate()
  }

  return (
    <div className="space-y-4 max-w-5xl">
      <nav className="text-sm">
        <Link to="/billing" className="text-blue-600 hover:underline">← К списку</Link>
      </nav>

      {!editMode ? (
        <div className="bg-white rounded-lg shadow p-5 space-y-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h1 className="text-xl font-bold">{data.contract_name || data.name || '—'}</h1>
              <p className="text-sm text-gray-600">{data.address || '—'}</p>
            </div>
            <div className="flex gap-2">
              <button type="button" onClick={() => setEditMode(true)} className="rounded border bg-white px-3 py-2 text-sm hover:bg-gray-100">
                Редактировать
              </button>
              <button type="button" onClick={() => setReadingMode((v) => !v)} className="rounded bg-blue-600 text-white px-3 py-2 text-sm hover:bg-blue-700">
                Ввести показания
              </button>
            </div>
          </div>

          <dl className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-y-3 gap-x-4 text-sm">
            {viewRow('Статус', data.status)}
            {viewRow('Номер договора', data.contract_number)}
            {viewRow('Улица', data.street)}
            {viewRow('Номер дома', data.house_number)}
            {viewRow('Назначение', data.purpose)}
            {viewRow('Назначение 2', data.purpose_2)}
            {viewRow('Дата проведения сверки показаний', data.reconciliation_date)}
            {viewRow('Дата следующей поверки', data.poverka_next)}
            {viewRow('Дата ввода в эксплуатацию', data.commissioned)}
            {viewRow('Заводской номер счетчика', data.serial)}
            {viewRow('Дата передачи конечных показаний', data.final_date)}
            {viewRow('Конечные показания', data.final_value)}
            {viewRow('Дата передачи текущих показаний', data.current_date)}
            {viewRow('Текущие показания', data.current_value)}
            {viewRow('V ГВС', data.volume_gvs)}
            {viewRow('Номер пломбы', data.seal_number)}
            {viewRow('Дата опломбировки', data.seal_date)}
            {viewRow('Тип прибора', data.meter_type)}
          </dl>

          {readingMode && (
            <form onSubmit={onSaveReading} className="border-t pt-4 flex flex-wrap items-end gap-3">
              <label className="flex flex-col">
                <span className="text-xs text-gray-500">Текущие показания</span>
                <input
                  className="rounded border px-2 py-1 text-sm w-44"
                  value={readingValue}
                  onChange={(e) => setReadingValue(e.target.value)}
                  placeholder="Введите значение"
                  inputMode="decimal"
                  autoFocus
                />
              </label>
              <div className="text-xs text-gray-500 pb-1">Дата: {todayRu()}</div>
              <button type="submit" className="rounded bg-green-600 text-white px-3 py-2 text-sm hover:bg-green-700" disabled={saveReading.isPending}>
                {saveReading.isPending ? 'Сохранение...' : 'Сохранить'}
              </button>
              <button type="button" className="rounded border bg-white px-3 py-2 text-sm hover:bg-gray-100" onClick={() => setReadingMode(false)}>
                Отмена
              </button>
            </form>
          )}
        </div>
      ) : (
        <form onSubmit={onSaveCard} className="bg-white rounded-lg shadow p-5 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <label className="flex flex-col">
              <span className="text-xs text-gray-500">Статус</span>
              <select className="rounded border px-2 py-1 text-sm" value={form.status || ''} onChange={(e) => setForm((prev) => ({ ...prev, status: e.target.value }))}>
                <option value="активный">активный</option>
                <option value="неактивный">неактивный</option>
              </select>
            </label>
            {renderInput('contract_name', 'Наименование по договору')}
            {renderInput('contract_number', 'Номер договора')}
            {renderInput('street', 'Улица')}
            {renderInput('house_number', 'Номер дома')}
            {renderInput('purpose', 'Назначение (1)')}
            {renderInput('purpose_2', 'Назначение (2)')}
            {renderInput('address', 'Адрес по договору')}
            {renderInput('reconciliation_date', 'Дата проведения сверки показаний')}
            {renderInput('poverka_next', 'Дата следующей поверки')}
            {renderInput('commissioned', 'Дата ввода в эксплуатацию')}
            {renderInput('serial', 'Заводской номер счетчика')}
            {renderInput('final_date', 'Дата передачи конечных показаний')}
            {renderInput('final_value', 'Конечные показания')}
            {renderInput('current_date', 'Дата передачи текущих показаний')}
            {renderInput('current_value', 'Текущие показания')}
            {renderInput('volume_gvs', 'V ГВС')}
            {renderInput('seal_number', 'Номер пломбы')}
            {renderInput('seal_date', 'Дата опломбировки')}
            {renderInput('meter_type', 'Тип прибора')}
          </div>
          <div className="flex gap-2">
            <button type="submit" className="rounded bg-blue-600 text-white px-4 py-2 text-sm" disabled={saveCard.isPending}>
              {saveCard.isPending ? 'Сохранение...' : 'Сохранить'}
            </button>
            <button
              type="button"
              className="rounded border bg-white px-4 py-2 text-sm hover:bg-gray-100"
              onClick={() => {
                setEditMode(false)
                setForm(data)
              }}
            >
              Отмена
            </button>
          </div>
        </form>
      )}
    </div>
  )
}

