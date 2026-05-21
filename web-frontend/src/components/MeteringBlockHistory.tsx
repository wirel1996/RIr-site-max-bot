import { useQuery } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { meteringApi } from '../api/metering'
import { meteringRu as t } from '../locales/ru/metering'

export type BlockHistoryField = { field: string; label: string }

type Props = {
  category: string
  recordId: number
  blockTitle: string
  fields: BlockHistoryField[]
}

export function collectBlockAuditFields(
  baseFields: Array<[string, string]>,
  displayFields: Array<[string, string]> = [],
): BlockHistoryField[] {
  const map = new Map<string, string>()
  const add = (key: string, label: string) => {
    const field = key.startsWith('extra_seal_') ? 'extra_seals_json' : key
    const lbl = field === 'extra_seals_json' ? 'Дополнительные пломбы' : label
    if (!map.has(field)) map.set(field, lbl)
  }
  baseFields.forEach(([key, label]) => add(key, label))
  displayFields.forEach(([key, label]) => add(key, label))
  if (map.has('date_input_uute') || map.has('date_output_uute')) {
    map.set('periods_json', 'Периоды эксплуатации')
  }
  return [...map.entries()].map(([field, label]) => ({ field, label }))
}

export default function MeteringBlockHistory({ category, recordId, blockTitle, fields }: Props) {
  const [open, setOpen] = useState(false)
  const auditFields = useMemo(() => fields.map((f) => f.field), [fields])
  const labelByField = useMemo(
    () => Object.fromEntries(fields.map((f) => [f.field, f.label])),
    [fields],
  )

  const query = useQuery({
    queryKey: ['metering', category, 'block-history', recordId, auditFields.join(',')],
    queryFn: () => meteringApi.blockHistory(category, recordId, auditFields),
    enabled: open && auditFields.length > 0,
  })

  if (fields.length === 0) return null

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="rounded border border-gray-200 bg-white px-2.5 py-1 text-xs text-gray-600 hover:bg-gray-50"
      >
        {t.detail.fieldHistory}
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-lg bg-white p-4 shadow-lg">
            <div className="mb-3 flex items-start justify-between gap-2">
              <h3 className="text-sm font-semibold">
                {t.detail.fieldHistoryTitle}: {blockTitle}
              </h3>
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="rounded border px-2 py-1 text-xs"
              >
                {t.detail.cancel}
              </button>
            </div>
            {query.isLoading && (
              <p className="text-sm text-gray-500">{t.detail.fieldHistoryLoading}</p>
            )}
            {query.error && (
              <p className="text-sm text-red-600">{(query.error as Error).message}</p>
            )}
            {!query.isLoading && !query.error && (query.data?.logs.length ?? 0) === 0 && (
              <p className="text-sm text-gray-500">{t.detail.fieldHistoryEmpty}</p>
            )}
            <div className="space-y-2">
              {query.data?.logs.map((log, idx) => (
                <div key={`${log.created_at}-${log.field}-${idx}`} className="rounded border border-gray-200 p-2 text-xs">
                  <div className="mb-1 font-medium text-gray-800">
                    {labelByField[log.field] || log.field}
                  </div>
                  <div>
                    <span className="font-semibold">{t.detail.fieldHistoryWho}:</span>{' '}
                    {log.actor_name || log.actor_login || '—'}
                  </div>
                  <div>
                    <span className="font-semibold">{t.detail.fieldHistoryWhen}:</span>{' '}
                    {new Date(log.created_at * 1000).toLocaleString('ru-RU')}
                  </div>
                  <div>
                    <span className="font-semibold">{t.detail.fieldHistoryOld}:</span>{' '}
                    <span className="whitespace-pre-wrap">{log.old_value || '—'}</span>
                  </div>
                  <div>
                    <span className="font-semibold">{t.detail.fieldHistoryNew}:</span>{' '}
                    <span className="whitespace-pre-wrap">{log.new_value || '—'}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </>
  )
}
