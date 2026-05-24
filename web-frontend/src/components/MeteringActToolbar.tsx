import { useQuery } from '@tanstack/react-query'
import { useEffect, useRef, useState } from 'react'
import type { ActKind, MeteringActDeletable } from '../api/metering'
import { meteringApi } from '../api/metering'
import { objectsApi } from '../api/objects'
import { useAuth } from '../contexts/AuthContext'
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

function defaultSpecialistName(
  authors: Array<{ login: string; name: string }>,
  login: string | undefined,
  fallbackName: string | undefined,
) {
  if (!login) return ''
  const hit = authors.find((a) => a.login === login)
  if (hit) return hit.name
  if (fallbackName && authors.some((a) => a.name === fallbackName)) return fallbackName
  return ''
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
  const { user, canDelete } = useAuth()
  const [enterOpen, setEnterOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [downloadOpen, setDownloadOpen] = useState(false)
  const [specialist, setSpecialist] = useState('')
  const rootRef = useRef<HTMLDivElement>(null)

  const authorsQuery = useQuery({
    queryKey: ['objects', 'switch-act-authors'],
    queryFn: () => objectsApi.switchActAuthors(),
  })
  const actAuthors = authorsQuery.data?.authors ?? []

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

  const openDownloadModal = () => {
    setEnterOpen(false)
    setDeleteOpen(false)
    setSpecialist(defaultSpecialistName(actAuthors, user?.login, user?.name))
    setDownloadOpen(true)
  }

  const confirmDownload = () => {
    if (!specialist.trim()) return
    window.location.assign(meteringApi.admissionActUrl(category, recordId, specialist.trim()))
    setDownloadOpen(false)
  }

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

      <button
        type="button"
        onClick={openDownloadModal}
        className="rounded border border-blue-200 bg-blue-50 px-3 py-1.5 text-sm text-blue-800 hover:bg-blue-100"
      >
        {t.detail.downloadAct}
      </button>

      {canDelete && (
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
      )}

      {downloadOpen && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/40 p-4 pt-16">
          <div
            className="w-full max-w-md rounded-lg bg-white p-5 shadow-xl"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <h3 className="text-lg font-semibold">{t.detail.downloadAct}</h3>
            <label className="mt-4 block text-sm">
              {t.detail.downloadActWho}
              <select
                value={specialist}
                onChange={(e) => setSpecialist(e.target.value)}
                className="mt-1 w-full rounded border px-3 py-2"
                disabled={authorsQuery.isLoading}
              >
                <option value="">
                  {authorsQuery.isLoading ? 'Загрузка...' : t.detail.downloadActSelect}
                </option>
                {actAuthors.map((author) => (
                  <option key={author.login} value={author.name}>
                    {author.name}
                  </option>
                ))}
              </select>
            </label>
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setDownloadOpen(false)}
                className="rounded border px-4 py-2 text-sm hover:bg-gray-50"
              >
                {t.detail.downloadActClose}
              </button>
              <button
                type="button"
                disabled={!specialist.trim() || authorsQuery.isLoading}
                onClick={confirmDownload}
                className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
              >
                {t.detail.downloadActConfirm}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
