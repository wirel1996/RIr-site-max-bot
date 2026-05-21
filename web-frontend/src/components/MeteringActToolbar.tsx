import { useEffect, useRef, useState } from 'react'
import type { ActKind, MeteringActDeletable } from '../api/metering'
import { meteringApi } from '../api/metering'
import { meteringRu as t } from '../locales/ru/metering'

type Props = {
  category: string
  recordId: number
  deletable: MeteringActDeletable[]
  onEnterAct: (kind: ActKind) => void
  onDeleteAct: (kind: ActKind) => void
  deletePending?: boolean
  deleteConfirm: Record<ActKind, string>
}

function replaceTemplate(template: string, n: string, label: string) {
  return template.replace('{{n}}', n).replace('{{label}}', label)
}

export default function MeteringActToolbar({
  category,
  recordId,
  deletable,
  onEnterAct,
  onDeleteAct,
  deletePending,
  deleteConfirm,
}: Props) {
  const [enterOpen, setEnterOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const onDoc = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) {
        setEnterOpen(false)
        setDeleteOpen(false)
      }
    }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])

  const enterItems: Array<{ kind: ActKind; label: string }> = [
    { kind: 'input', label: t.detail.enterActInput },
    { kind: 'check', label: t.detail.enterActCheck },
    { kind: 'output', label: t.detail.enterActOutput },
  ]

  return (
    <div ref={rootRef} className="flex shrink-0 flex-wrap items-center gap-2">
      <div className="relative">
        <button
          type="button"
          onClick={() => {
            setDeleteOpen(false)
            setEnterOpen((v) => !v)
          }}
          className="rounded border border-emerald-200 bg-emerald-50 px-3 py-1.5 text-sm text-emerald-800 hover:bg-emerald-100"
        >
          {t.detail.enterAct} ▾
        </button>
        {enterOpen && (
          <div className="absolute right-0 z-40 mt-1 min-w-[10rem] rounded border bg-white py-1 shadow">
            {enterItems.map((item) => (
              <button
                key={item.kind}
                type="button"
                className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50"
                onClick={() => {
                  onEnterAct(item.kind)
                  setEnterOpen(false)
                }}
              >
                {item.label}
              </button>
            ))}
          </div>
        )}
      </div>

      <a
        href={meteringApi.admissionActUrl(category, recordId)}
        className="rounded border border-blue-200 bg-blue-50 px-3 py-1.5 text-sm text-blue-800 hover:bg-blue-100"
      >
        {t.detail.downloadAct}
      </a>

      <div className="relative">
        <button
          type="button"
          disabled={deletePending}
          onClick={() => {
            setEnterOpen(false)
            setDeleteOpen((v) => !v)
          }}
          className="rounded border border-amber-200 bg-amber-50 px-3 py-1.5 text-sm text-amber-900 hover:bg-amber-100 disabled:opacity-50"
        >
          {deletePending ? t.detail.saving : `${t.detail.deleteAct} ▾`}
        </button>
        {deleteOpen && (
          <div className="absolute right-0 z-40 mt-1 min-w-[12rem] rounded border bg-white py-1 shadow">
            {deletable.length === 0 ? (
              <p className="px-3 py-2 text-sm text-gray-500">{t.detail.deleteActNone}</p>
            ) : (
              deletable.map((item) => (
                <button
                  key={item.kind}
                  type="button"
                  className="w-full px-3 py-2 text-left text-sm text-amber-900 hover:bg-amber-50"
                  onClick={() => {
                    if (!window.confirm(deleteConfirm[item.kind])) return
                    onDeleteAct(item.kind)
                    setDeleteOpen(false)
                  }}
                >
                  {replaceTemplate(t.detail.deleteActItem, item.act_number, item.label)}
                </button>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  )
}
