import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { meteringApi, type ActKind, type MeteringActHistoryEvent } from '../api/metering'
import { meteringRu as t } from '../locales/ru/metering'
import { meteringFieldLabel } from '../pages/metering/meteringFieldLabels'

type Props = {
  category: string
  recordId: number
}

const KIND_LABEL: Record<ActKind, string> = {
  input: t.detail.actKindInput,
  check: t.detail.actKindCheck,
  output: t.detail.actKindOutput,
}

function actorName(row: MeteringActHistoryEvent) {
  return row.actor_name || row.actor_login || '—'
}

export default function MeteringActHistory({ category, recordId }: Props) {
  const [open, setOpen] = useState(true)
  const [expanded, setExpanded] = useState<number | null>(null)

  const query = useQuery({
    queryKey: ['metering', category, 'act-history', String(recordId)],
    queryFn: () => meteringApi.actHistory(category, recordId),
    enabled: !!recordId,
  })

  const events = query.data?.events ?? []

  return (
    <section className="rounded-lg bg-white p-5 shadow">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="mb-3 flex w-full items-center justify-between text-left font-semibold"
      >
        <span>{t.detail.actHistoryTitle}</span>
        <span className="text-xs font-normal text-gray-500">{open ? '▼' : '▶'}</span>
      </button>

      {open && (
        <>
          {query.isLoading && (
            <p className="text-sm text-gray-500">{t.detail.actHistoryLoading}</p>
          )}
          {query.error && (
            <p className="text-sm text-red-600">{(query.error as Error).message}</p>
          )}
          {!query.isLoading && !query.error && events.length === 0 && (
            <p className="text-sm text-gray-500">{t.detail.actHistoryEmpty}</p>
          )}
          {events.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[36rem] border-collapse text-sm">
                <thead>
                  <tr className="border-b text-left text-xs text-gray-500">
                    <th className="py-2 pr-3">{t.detail.actHistoryNumber}</th>
                    <th className="py-2 pr-3">{t.detail.actHistoryKind}</th>
                    <th className="py-2 pr-3">{t.detail.actHistoryDate}</th>
                    <th className="py-2 pr-3">{t.detail.actHistoryWhen}</th>
                    <th className="py-2 pr-3">{t.detail.actHistoryWho}</th>
                    <th className="py-2">{t.detail.actHistoryChanges}</th>
                  </tr>
                </thead>
                <tbody>
                  {events.map((row, idx) => {
                    const isExpanded = expanded === idx
                    const num = row.act_number?.trim() || '—'
                    return (
                      <tr key={`${row.created_at}-${row.kind}-${idx}`} className="border-b align-top">
                        <td className="py-2 pr-3 font-medium">{num}</td>
                        <td className="py-2 pr-3">{KIND_LABEL[row.kind]}</td>
                        <td className="py-2 pr-3">{row.act_date || '—'}</td>
                        <td className="py-2 pr-3 whitespace-nowrap">
                          {new Date(row.created_at * 1000).toLocaleString('ru-RU')}
                        </td>
                        <td className="py-2 pr-3">{actorName(row)}</td>
                        <td className="py-2">
                          {row.changes.length === 0 ? (
                            '—'
                          ) : (
                            <>
                              <button
                                type="button"
                                className="text-xs text-blue-600 hover:underline"
                                onClick={() => setExpanded(isExpanded ? null : idx)}
                              >
                                {isExpanded ? t.detail.actHistoryHideChanges : t.detail.actHistoryShowChanges}
                                {` (${row.changes.length})`}
                              </button>
                              {isExpanded && (
                                <ul className="mt-2 space-y-1 text-xs text-gray-700">
                                  {row.changes.map((ch) => (
                                    <li key={ch.field} className="rounded border border-gray-100 bg-gray-50 p-1.5">
                                      <span className="font-medium">{meteringFieldLabel(ch.field)}</span>
                                      <div>
                                        <span className="text-gray-500">{t.detail.fieldHistoryOld}:</span>{' '}
                                        {ch.old_value || '—'}
                                      </div>
                                      <div>
                                        <span className="text-gray-500">{t.detail.fieldHistoryNew}:</span>{' '}
                                        {ch.new_value || '—'}
                                      </div>
                                    </li>
                                  ))}
                                </ul>
                              )}
                            </>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </section>
  )
}
