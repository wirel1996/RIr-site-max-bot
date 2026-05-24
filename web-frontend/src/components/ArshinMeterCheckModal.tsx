import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { arshinApi, type ArshinItem } from '../api/arshin'
import type { MeteringRecord } from '../api/metering'
import type { ArshinMeterDevice } from './arshinMeterDevices'
import { getPreferredMitNotation, savePreferredMitNotation } from '../utils/arshinTypePrefs'
import { buildArshinSerialCandidates } from '../utils/arshinSerialCandidates'

export type { ArshinMeterDevice } from './arshinMeterDevices'

function applicabilityOk(item: ArshinItem) {
  const value = item.applicability
  return value === true || String(value).toLowerCase() === 'да'
}

type Props = {
  open: boolean
  uuteId: number
  device: ArshinMeterDevice | null
  record: MeteringRecord
  initialSearch?: {
    serial?: string
    text: string
    items: ArshinItem[]
    used_preferred_type?: boolean
  } | null
  onClose: () => void
  onApplied?: (record: MeteringRecord) => void
}

export default function ArshinMeterCheckModal({ open, uuteId, device, record, initialSearch, onClose, onApplied }: Props) {
  const queryClient = useQueryClient()
  const serialFromDb = device ? String(record[device.serialKey] ?? '').trim() : ''
  const validUntilFromDb = device ? String(record[device.dateKey] ?? '').trim() : ''
  const preferredType = device ? getPreferredMitNotation(device.serialKey) : undefined

  const [editableSerial, setEditableSerial] = useState(serialFromDb)
  const [resultDocnum, setResultDocnum] = useState('')
  const [year, setYear] = useState('')
  const [orgTitle, setOrgTitle] = useState('')
  const [message, setMessage] = useState('')
  const [serialMismatch, setSerialMismatch] = useState<{
    serial_key: string
    current: string
    found: string
  } | null>(null)
  const [cachedResult, setCachedResult] = useState<{
    text: string
    items: ArshinItem[]
    used_preferred_type?: boolean
  } | null>(null)
  const isTempSensor = device?.serialKey === 'temp_sensor_serial_1' || device?.serialKey === 'temp_sensor_serial_2'
  const mitNotation = isTempSensor
    ? (device?.serialKey === 'temp_sensor_serial_1' ? record.temp_sensor_1 : record.temp_sensor_2)
    : undefined

  const opts = useQuery({
    queryKey: ['arshin', 'options'],
    queryFn: () => arshinApi.options(),
    enabled: open,
  })

  const search = useMutation({
    mutationFn: () => {
      return arshinApi.searchMeter({
        serial: editableSerial.trim(),
        serial_candidates: editableSerial.trim() === serialFromDb ? buildArshinSerialCandidates(record, device?.serialKey) : undefined,
        result_docnum: resultDocnum.trim() || undefined,
        valid_until: validUntilFromDb || undefined,
        year: year.trim() || undefined,
        org_title: orgTitle.trim() || undefined,
        preferred_mit_notation: preferredType,
        mit_notation: mitNotation || undefined,
        serial_key: device?.serialKey,
        meter_label: device?.label,
      })
    },
  })

  useEffect(() => {
    if (!open || !initialSearch) return
    if (initialSearch.serial) setEditableSerial(initialSearch.serial)
    setCachedResult({
      text: initialSearch.text,
      items: initialSearch.items,
      used_preferred_type: initialSearch.used_preferred_type,
    })
  }, [open, initialSearch])

  const apply = useMutation({
    mutationFn: (item: ArshinItem) =>
      arshinApi.applyMeter(uuteId, {
        serial_key: device!.serialKey,
        item,
        
      }),
    onSuccess: (result, item) => {
      queryClient.setQueryData(['metering', 'detail', String(uuteId)], result.record)
      queryClient.invalidateQueries({ queryKey: ['metering', 'gspo'] })

      if (item?.mit_notation && device) {
        savePreferredMitNotation(device.serialKey, item.mit_notation)
      }

      if (result.serial_mismatch) {
        setSerialMismatch(result.serial_mismatch)
      } else {
        onApplied?.(result.record)
      }

      setMessage('Данные из АРШИН сохранены в карточку.')
    },
    onError: (err: Error) => setMessage(err.message || 'Не удалось применить'),
  })

  const runSearch = () => {
    if (!device || (!editableSerial.trim() && !resultDocnum.trim())) return
    setMessage('')
    setCachedResult(null)
    search.mutate()
  }

  const updateSerial = () => {
    if (!serialMismatch) return
    const field = serialMismatch.serial_key
    fetch(`/api/metering/gspo/${uuteId}`, {
      method: 'PATCH',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ [field]: serialMismatch.found }),
    })
      .then((res) => {
        if (!res.ok) throw new Error('Не удалось обновить номер')
        return res.json()
      })
      .then(() => {
        queryClient.invalidateQueries({ queryKey: ['metering', 'detail', String(uuteId)] })
        queryClient.invalidateQueries({ queryKey: ['metering', 'gspo'] })
        setEditableSerial(serialMismatch.found)
        setMessage(`Номер обновлён: ${serialMismatch.current} → ${serialMismatch.found}`)
        onApplied?.(queryClient.getQueryData(['metering', 'detail', String(uuteId)]) as MeteringRecord)
        setSerialMismatch(null)
      })
      .catch((err: Error) => setMessage(err.message))
  }

  if (!open || !device) return null

  return (
    <div key={`${uuteId}-${device.serialKey}`} className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4">
      <div className="flex max-h-[90vh] w-full max-w-2xl flex-col rounded-lg bg-white shadow-xl">
        <div className="border-b p-4">
          <h2 className="text-lg font-semibold">Проверка в АРШИН</h2>
          <p className="mt-1 text-sm text-gray-600">{device.label}</p>
          {preferredType && (
            <p className="mt-1 text-xs text-emerald-700">
              Приоритетный тип: {preferredType}
            </p>
          )}
        </div>

        <div className="space-y-3 overflow-y-auto p-4">
          <label className="block text-sm">
            <span className="mb-1 block text-gray-700">Заводской номер</span>
            <input
              type="text"
              value={editableSerial}
              onChange={(event) => setEditableSerial(event.target.value)}
              onKeyDown={(event) => { if (event.key === 'Enter') runSearch() }}
              className="w-full rounded border px-3 py-2 text-sm"
              placeholder="Введите номер прибора"
            />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block text-gray-700">Номер свидетельства</span>
            <input
              type="text"
              value={resultDocnum}
              onChange={(event) => setResultDocnum(event.target.value)}
              onKeyDown={(event) => { if (event.key === 'Enter') runSearch() }}
              className="w-full rounded border px-3 py-2 text-sm"
              placeholder="Например: С-ЕВК/10-03-2026/510413687"
            />
          </label>

          {isTempSensor && (
            <p className="text-xs text-amber-700">
              Для датчиков температуры номер может быть парным (например, с суффиксом «г/х»). Если по чистому номеру не найдено, попробуйте добавить «г/х».
            </p>
          )}
          <p className="text-xs text-gray-500">
            {year.trim()
              ? `Поиск в году ${year}`
              : 'Автопоиск по годам с текущего и шести предыдущих'}
          </p>
          <label className="block text-sm">
            <span className="mb-1 block text-gray-700">Год поверки</span>
            <select
              value={year}
              onChange={(event) => setYear(event.target.value)}
              className="w-full rounded border bg-white px-3 py-2 text-sm"
            >
              <option value="">Авто</option>
              {(opts.data?.years ?? []).map((y) => (
                <option key={y} value={y}>{y}</option>
              ))}
            </select>
          </label>
          <label className="block text-sm">
            <span className="mb-1 block text-gray-700">Поверитель</span>
            <select
              value={orgTitle}
              onChange={(event) => setOrgTitle(event.target.value)}
              className="w-full rounded border bg-white px-3 py-2 text-sm"
            >
              <option value="">— не фильтровать —</option>
              {(opts.data?.orgs ?? []).map((org) => (
                <option key={org} value={org}>{org}</option>
              ))}
            </select>
          </label>

          <button
            type="button"
            disabled={search.isPending || (!editableSerial.trim() && !resultDocnum.trim())}
            onClick={runSearch}
            className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
          >
            {search.isPending ? 'Ищу...' : 'Найти в АРШИН'}
          </button>

          {message && (
            <div className="rounded border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900">{message}</div>
          )}

          {search.error && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
              {(search.error as Error).message || 'Ошибка запроса'}
            </div>
          )}

          {serialMismatch && (
            <div className="rounded border border-amber-300 bg-amber-50 p-4">
              <p className="text-sm font-medium text-amber-900">
                Номер в АРШИН отличается от номера в базе
              </p>
              <p className="mt-1 text-sm text-amber-800">
                В базе: <strong>{serialMismatch.current}</strong>
                {' '}→ В АРШИН: <strong>{serialMismatch.found}</strong>
              </p>
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  onClick={updateSerial}
                  className="rounded bg-amber-600 px-3 py-1.5 text-sm text-white hover:bg-amber-700"
                >
                  Обновить номер в базе
                </button>
                <button
                  type="button"
                  onClick={() => setSerialMismatch(null)}
                  className="rounded border border-amber-300 bg-white px-3 py-1.5 text-sm text-amber-800 hover:bg-amber-100"
                >
                  Оставить как есть
                </button>
              </div>
            </div>
          )}

          {(cachedResult || search.data) && (
            <div className="space-y-3">
              {(cachedResult?.used_preferred_type || search.data?.used_preferred_type) && (
                <p className="text-xs text-emerald-700">Найдено по приоритетному типу</p>
              )}
              <pre className="whitespace-pre-wrap rounded border bg-gray-50 p-3 text-sm font-sans">
                {cachedResult?.text ?? search.data?.text}
              </pre>
              {(cachedResult?.items ?? search.data?.items ?? []).map((item, i) => {
                const ok = applicabilityOk(item)
                return (
                  <div
                    key={i}
                    className={`rounded border p-3 text-sm ${ok ? 'border-emerald-200 bg-emerald-50/60' : 'border-red-300 bg-red-50'}`}
                  >
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                      <div>
                        <div className="font-medium">
                          #{i + 1} · {item.mi_number || '—'}
                        </div>
                        <p className="text-gray-700">{item.mit_notation || ''}</p>
                        <p className="mt-1">
                          Действительна до:{' '}
                          <span className="font-medium">{item.valid_date || '—'}</span>
                        </p>
                        <p className="text-gray-600">Дата поверки: {item.verification_date || '—'}</p>
                        <p className="text-gray-600">{item.org_title || ''}</p>
                        {item.registry_url && (
                          <a
                            href={item.registry_url}
                            target="_blank"
                            rel="noreferrer"
                            className="mt-2 inline-block text-sm font-medium text-blue-700 hover:underline"
                          >
                            Открыть запись в АРШИН
                          </a>
                        )}
                        <p className={`mt-2 inline-block rounded px-2 py-0.5 text-xs font-semibold ${ok ? 'bg-emerald-200 text-emerald-900' : 'bg-red-200 text-red-900'}`}>
                          Пригодность: {ok ? 'Да' : 'Нет'}
                        </p>
                      </div>
                      <button
                        type="button"
                        disabled={apply.isPending}
                        onClick={() => apply.mutate(item)}
                        className="shrink-0 rounded bg-blue-600 px-3 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
                      >
                        {apply.isPending ? '…' : 'Применить'}
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>

        <div className="flex justify-end border-t p-4">
          <button
            type="button"
            onClick={onClose}
            className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
          >
            Закрыть
          </button>
        </div>
      </div>
    </div>
  )
}

