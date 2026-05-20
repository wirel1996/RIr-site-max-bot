import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useCallback, useEffect, useRef, useState } from 'react'
import { journalApi, type JournalWeek, type JournalWeekData } from '../../api/journal'
import { journalRu as t } from '../../locales/ru/journal'

type CellPos = { date: string; time: string; person: string }

function pickInitialWeek(weeks: JournalWeek[]): string | null {
  const todayIso = new Date().toISOString().slice(0, 10)
  const todayWeek = weeks.find((w) => w.contains_today)
  if (todayWeek) return todayWeek.start
  const notFutureWithData = weeks.filter((w) => w.has_data && w.start <= todayIso)
  if (notFutureWithData.length > 0) return notFutureWithData[notFutureWithData.length - 1].start
  const withData = weeks.filter((w) => w.has_data)
  if (withData.length > 0) return withData[0].start
  return weeks[0]?.start ?? null
}

function cellKey(date: string, time: string, person: string) {
  return `${date}|${time}|${person}`
}

function fmtIso(iso: string) {
  return iso.split('-').reverse().join('.')
}

/** Живое обновление журнала в открытой вкладке. */
const JOURNAL_LIVE_REFRESH_MS = 5_000
const JOURNAL_HOTKEY_DEBUG = true

function journalHotkeyDebug(message: string, data?: unknown) {
  if (!JOURNAL_HOTKEY_DEBUG) return
  console.debug(`[journal-hotkey] ${message}`, data ?? '')
}

function JournalCell({
  value,
  selected,
  multiSelected,
  color,
  isFirstSlot,
  readOnly,
  saving,
  onSelect,
  onSave,
  onAuditClick,
}: {
  value: string
  selected: boolean
  multiSelected?: boolean
  color?: string
  isFirstSlot?: boolean
  readOnly?: boolean
  saving?: boolean
  onSelect: (e: React.MouseEvent) => void
  onSave: (v: string) => Promise<void>
  onAuditClick: () => void
}) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)
  const openingEditorRef = useRef(false)
  const editorRef = useRef<HTMLTextAreaElement | null>(null)
  useEffect(() => {
    if (!editing) setDraft(value)
  }, [value, editing])
  useEffect(() => {
    if (!editing || !editorRef.current) return
    const len = editorRef.current.value.length
    editorRef.current.setSelectionRange(len, len)
  }, [editing])

  if (editing) {
    return (
      <div className="absolute inset-0 z-10 bg-white border-2 border-blue-500">
        <textarea
          ref={editorRef}
          autoFocus
          disabled={saving}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={() => {
            if (saving) return
            setEditing(false)
            if (draft !== value) void onSave(draft)
          }}
          className="w-full h-full p-1 text-xs resize-none focus:outline-none disabled:opacity-60"
        />
      </div>
    )
  }

  const bgClass = color ? '' : isFirstSlot ? 'bg-gray-50' : ''
  const ringClass = selected ? 'ring-2 ring-blue-500 ring-inset' : multiSelected ? 'ring-2 ring-blue-300 ring-inset' : 'hover:bg-blue-50'
  return (
    <div
      tabIndex={0}
      className={`relative w-full h-full p-1 text-xs whitespace-pre-wrap overflow-hidden cursor-pointer ${bgClass} ${ringClass}`}
      style={color ? { backgroundColor: color } : undefined}
      onClick={(e) => {
        onSelect(e)
        ;(e.currentTarget as HTMLDivElement).focus()
      }}
      onDoubleClick={() => {
        if (readOnly) {
          window.alert(t.alerts.dayNotCreated)
          return
        }
        setEditing(true)
      }}
      onKeyDown={(e) => {
        if (readOnly || saving) return
        if (openingEditorRef.current) {
          e.preventDefault()
          return
        }
        if (e.key === 'Enter' || e.key === 'F2') {
          e.preventDefault()
          openingEditorRef.current = true
          setEditing(true)
          window.setTimeout(() => { openingEditorRef.current = false }, 80)
          return
        }
        if (e.key === 'Delete') {
          e.preventDefault()
          if (value !== '') void onSave('')
          return
        }
        if (e.key === 'Backspace') {
          e.preventDefault()
          const next = value.slice(0, -1)
          openingEditorRef.current = true
          setDraft(next)
          setEditing(true)
          window.setTimeout(() => { openingEditorRef.current = false }, 80)
          return
        }
        if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
          e.preventDefault()
          openingEditorRef.current = true
          setDraft(e.key)
          setEditing(true)
          window.setTimeout(() => { openingEditorRef.current = false }, 80)
          return
        }
        if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
          e.preventDefault()
          openingEditorRef.current = true
          setDraft(e.key)
          setEditing(true)
          window.setTimeout(() => { openingEditorRef.current = false }, 80)
          return
        }
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'c') {
          e.preventDefault()
          void navigator.clipboard.writeText(value ?? '').catch(() => {})
          return
        }
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'x') {
          e.preventDefault()
          void navigator.clipboard.writeText(value ?? '').then(() => {
            if (value !== '') void onSave('')
          }).catch(() => {})
        }
      }}
      title={readOnly ? t.cell.dayNotInGoogle : value}
    >
      {saving ? <span className="text-gray-400">…</span> : value || <span className="text-gray-300">·</span>}
      <button
        type="button"
        className="absolute top-0 right-0 text-[10px] px-1 text-gray-500 hover:text-blue-700"
        onClick={(e) => {
          e.stopPropagation()
          onAuditClick()
        }}
      >
        !
      </button>
    </div>
  )
}

export default function Journal() {
  const queryClient = useQueryClient()
  const tabsRef = useRef<HTMLDivElement>(null)

  const [activeWeek, setActiveWeek] = useState<string | null>(null)
  const [selectedCells, setSelectedCells] = useState<Set<string>>(new Set())
  const [lastSelectedCell, setLastSelectedCell] = useState<CellPos | null>(null)
  const [cellColors, setCellColors] = useState<Record<string, string>>({})
  const [auditModal, setAuditModal] = useState<{ open: boolean; date: string; time: string; person: string; loading: boolean; error: string; logs: Array<{ created_at: number; actor_name: string; actor_login: string; old_value: string; new_value: string }> }>({ open: false, date: '', time: '', person: '', loading: false, error: '', logs: [] })
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const [searchOpen, setSearchOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [renameDraft, setRenameDraft] = useState<Record<string, string>>({})
  const [lastGoodWeekData, setLastGoodWeekData] = useState<JournalWeekData | null>(null)
  const [lastGoodWeeks, setLastGoodWeeks] = useState<JournalWeek[]>([])

  const weeksQ = useQuery({
    queryKey: ['journal', 'weeks'],
    queryFn: () => journalApi.weeks(),
    refetchInterval: (query) => {
      const weeks = (query.state.data as { weeks?: JournalWeek[] } | undefined)?.weeks ?? []
      // РџРѕСЃР»Рµ РїРµСЂРµР·Р°РїСѓСЃРєР° API РјРѕР¶РµС‚ РѕС‚РґР°С‚СЊ РїСѓСЃС‚РѕР№ СЃРїРёСЃРѕРє РЅР° РїРµСЂРІРѕРј С‡С‚РµРЅРёРё:
      // РјСЏРіРєРѕ РїРµСЂРµРїСЂРѕРІРµСЂСЏРµРј, РїРѕРєР° РЅРµРґРµР»Рё РЅРµ РїРѕСЏРІСЏС‚СЃСЏ.
      return weeks.length === 0 ? 5000 : false
    },
  })
  useEffect(() => {
    if (!activeWeek && weeksQ.data) setActiveWeek(pickInitialWeek(weeksQ.data.weeks))
  }, [weeksQ.data, activeWeek])
  useEffect(() => {
    const weeks = weeksQ.data?.weeks ?? []
    if (weeks.length > 0) setLastGoodWeeks(weeks)
  }, [weeksQ.data])
  useEffect(() => {
    if (!activeWeek || !tabsRef.current) return
    const el = tabsRef.current.querySelector(`[data-week="${activeWeek}"]`)
    el?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' })
  }, [activeWeek])
  useEffect(() => {
    setSelectedCells(new Set())
    setLastSelectedCell(null)
  }, [activeWeek])

  const weekDataQ = useQuery({
    queryKey: ['journal', 'week', activeWeek],
    queryFn: () => journalApi.week(activeWeek!),
    enabled: !!activeWeek,
    placeholderData: keepPreviousData,
    staleTime: 0,
    refetchOnWindowFocus: true,
    refetchInterval: JOURNAL_LIVE_REFRESH_MS,
    refetchIntervalInBackground: false,
  })
  useEffect(() => {
    if (weekDataQ.data?.colors) {
      setCellColors(weekDataQ.data.colors)
    } else {
      setCellColors({})
    }
  }, [weekDataQ.data])
  useEffect(() => {
    if (weekDataQ.data) setLastGoodWeekData(weekDataQ.data)
  }, [weekDataQ.data])

  const saveCell = useMutation({
    mutationFn: (payload: { date: string; time: string; person: string; value: string; oldValue: string }) =>
      journalApi.writeCell(payload.date, payload.time, payload.person, payload.value, payload.oldValue),
    onMutate: async (payload) => {
      const key = ['journal', 'week', activeWeek] as const
      const prev = queryClient.getQueryData<JournalWeekData>(key)
      if (prev) {
        const values = { ...prev.values }
        values[payload.date] = { ...(values[payload.date] ?? {}) }
        values[payload.date][payload.time] = {
          ...(values[payload.date][payload.time] ?? {}),
          [payload.person]: payload.value,
        }
        queryClient.setQueryData(key, { ...prev, values })
      }
      return { prev }
    },
    onError: (err, _payload, ctx) => {
      if (ctx?.prev) queryClient.setQueryData(['journal', 'week', activeWeek], ctx.prev)
      const msg = (err as { message?: string })?.message || 'Не удалось сохранить ячейку'
      window.alert(msg)
    },
    onSettled: (_data, error) => {
      if (error) queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] })
    },
  })

  const saveCellColors = useMutation({
    mutationFn: (cells: Array<{ date: string; time: string; person: string; color: string }>) =>
      journalApi.writeCellColors(cells),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] })
    },
  })

  const createNext = useMutation({
    mutationFn: () => journalApi.createNextWeek(),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['journal', 'weeks'] })
      setActiveWeek(res.start)
    },
  })
  const addColumn = useMutation({
    mutationFn: ({ start, name }: { start: string; name: string }) => journalApi.addColumn(start, name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] }),
  })
  const deleteColumn = useMutation({
    mutationFn: ({ start, name }: { start: string; name: string }) => journalApi.deleteColumn(start, name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] }),
  })
  const renameColumns = useMutation({
    mutationFn: ({ start, mapping }: { start: string; mapping: Record<string, string> }) => journalApi.renameColumns(start, mapping),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] }),
  })
  const addSaturday = useMutation({
    mutationFn: (start: string) => journalApi.enableSaturday(start),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] }),
  })
  const searchM = useMutation({ mutationFn: (q: string) => journalApi.search(q, 100) })

  const tableData = weekDataQ.data ?? lastGoodWeekData
  const weekLoading = Boolean(activeWeek) && !tableData && weekDataQ.isFetching
  const loadingOtherWeek = Boolean(tableData) && weekDataQ.isPlaceholderData && weekDataQ.isFetching
  const stableWeeks = (weeksQ.data?.weeks?.length ?? 0) > 0 ? (weeksQ.data?.weeks ?? []) : lastGoodWeeks
  const orderedWeeks = [...stableWeeks].reverse()
  const savingCellKey =
    saveCell.isPending && saveCell.variables
      ? cellKey(saveCell.variables.date, saveCell.variables.time, saveCell.variables.person)
      : ''
  const activeWeekMeta = orderedWeeks.find((w) => w.start === activeWeek)
  const people = tableData?.people ?? []
  const tableMinWidth = 130 + people.length * 70
  const todayIso = new Date().toISOString().slice(0, 10)
  const tableContainerRef = useRef<HTMLDivElement>(null)
  const hasScrolledRef = useRef(false)

  useEffect(() => {
    if (!tableData || !tableContainerRef.current || hasScrolledRef.current) return
    const container = tableContainerRef.current
    const todayRow = container.querySelector(`[data-date="${todayIso}"]`) as HTMLElement | null
    if (todayRow) {
      const rowRect = todayRow.getBoundingClientRect()
      const containerRect = container.getBoundingClientRect()
      const relativeTop = rowRect.top - containerRect.top + container.scrollTop
      container.scrollTop = Math.max(0, relativeTop - 50)
      hasScrolledRef.current = true
    }
  }, [tableData])

  useEffect(() => {
    hasScrolledRef.current = false
  }, [activeWeek])

  const selectedCellRef = useRef<CellPos | null>(null)
  useEffect(() => {
    selectedCellRef.current = lastSelectedCell
  }, [lastSelectedCell])

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const isMod = e.ctrlKey || e.metaKey
      journalHotkeyDebug('keydown', {
        key: e.key,
        code: e.code,
        ctrl: e.ctrlKey,
        meta: e.metaKey,
        alt: e.altKey,
        target: (e.target as HTMLElement | null)?.tagName,
        selectedCell: selectedCellRef.current,
      })
      if (!isMod) return
      const code = e.code
      const key =
        code === 'KeyC' ? 'c' :
        code === 'KeyV' ? 'v' :
        code === 'KeyX' ? 'x' :
        e.key.toLowerCase()
      if (key !== 'c' && key !== 'v' && key !== 'x') {
        journalHotkeyDebug('ignored: unsupported key', { key, code })
        return
      }

      const cell = selectedCellRef.current
      if (!cell) {
        journalHotkeyDebug('ignored: no selected cell')
        return
      }

      // Не перехватываем когда textarea в режиме редактирования
      if ((e.target as HTMLElement).tagName === 'TEXTAREA') {
        journalHotkeyDebug('ignored: textarea editing')
        return
      }

      if (key === 'c') {
        e.preventDefault()
        journalHotkeyDebug('copy', { cell })
        void navigator.clipboard.writeText(
          tableData?.values[cell.date]?.[cell.time]?.[cell.person] ?? ''
        )
        return
      }

      if (key === 'v') {
        e.preventDefault()
        journalHotkeyDebug('paste start', { cell })
        void navigator.clipboard.readText().then((text) => {
          const current = tableData?.values[cell.date]?.[cell.time]?.[cell.person] ?? ''
          journalHotkeyDebug('paste text', { cell, text, current })
          if (text !== current) {
            journalApi.writeCell(cell.date, cell.time, cell.person, text, current)
              .then(() => {
                queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] })
              })
              .catch((err) => {
                window.alert((err as { message?: string })?.message || 'Не удалось сохранить')
              })
          }
        }).catch(() => {})
        return
      }

      if (key === 'x') {
        e.preventDefault()
        const current = tableData?.values[cell.date]?.[cell.time]?.[cell.person] ?? ''
        journalHotkeyDebug('cut', { cell, current })
        void navigator.clipboard.writeText(current).then(() => {
          if (current !== '') {
            journalApi.writeCell(cell.date, cell.time, cell.person, '', current)
              .then(() => {
                queryClient.invalidateQueries({ queryKey: ['journal', 'week', activeWeek] })
              })
              .catch((err) => {
                window.alert((err as { message?: string })?.message || 'Не удалось сохранить')
              })
          }
        }).catch(() => {})
        return
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [tableData, activeWeek, queryClient])

  const handleCellSelect = useCallback((cell: CellPos) => (e: React.MouseEvent) => {
    const key = cellKey(cell.date, cell.time, cell.person)
    if (e.ctrlKey || e.metaKey) {
      setSelectedCells((prev) => {
        const next = new Set(prev)
        if (next.has(key)) {
          next.delete(key)
        } else {
          next.add(key)
        }
        return next
      })
      setLastSelectedCell(cell)
    } else if (e.shiftKey && lastSelectedCell) {
      const allDates = tableData?.days.map(d => d.date) ?? []
      const allTimes = tableData?.time_slots ?? []
      const allPeople = tableData?.people ?? []

      const s = lastSelectedCell
      const dateMin = allDates.indexOf(s.date)
      const dateMax = allDates.indexOf(cell.date)
      const dStart = Math.min(dateMin, dateMax)
      const dEnd = Math.max(dateMin, dateMax)

      const tStart = Math.min(allTimes.indexOf(s.time), allTimes.indexOf(cell.time))
      const tEnd = Math.max(allTimes.indexOf(s.time), allTimes.indexOf(cell.time))

      const pStart = Math.min(allPeople.indexOf(s.person), allPeople.indexOf(cell.person))
      const pEnd = Math.max(allPeople.indexOf(s.person), allPeople.indexOf(cell.person))

      const newSet = new Set(selectedCells)
      for (let di = dStart; di <= dEnd; di++) {
        const date = allDates[di]
        if (!date) continue
        const dayData = tableData?.days.find(d => d.date === date)
        const daySlots = dayData?.time_slots ?? allTimes
        for (let ti = tStart; ti <= tEnd; ti++) {
          const time = daySlots[ti] ?? allTimes[ti]
          if (!time) continue
          for (let pi = pStart; pi <= pEnd; pi++) {
            const person = allPeople[pi]
            if (!person) continue
            newSet.add(cellKey(date, time, person))
          }
        }
      }
      setSelectedCells(newSet)
      setLastSelectedCell(cell)
    } else {
      setSelectedCells(new Set([key]))
      setLastSelectedCell(cell)
    }
  }, [lastSelectedCell, selectedCells, tableData])

  const applyColor = useCallback((fill: 'none' | 'gray' | 'yellow' | 'green' | 'red' | 'blue') => {
    const toHex: Record<string, string> = {
      none: '',
      gray: '#ededed',
      yellow: '#fff2bf',
      green: '#d7efd7',
      red: '#f7d7d7',
      blue: '#d9e8fa',
    }
    const hex = toHex[fill]

    if (selectedCells.size === 0) return

    const newColors: Record<string, string> = { ...cellColors }
    const apiCells: Array<{ date: string; time: string; person: string; color: string }> = []
    selectedCells.forEach((key) => {
      newColors[key] = hex
      const [date, time, person] = key.split('|')
      if (date && time && person) {
        apiCells.push({ date, time, person, color: hex })
      }
    })
    setCellColors(newColors)
    saveCellColors.mutate(apiCells)
  }, [selectedCells, cellColors, saveCellColors])

  const openAuditModal = async (date: string, time: string, person: string) => {
    setAuditModal({ open: true, date, time, person, loading: true, error: '', logs: [] })
    try {
      const res = await journalApi.cellAuditHistory(date, time, person, 20)
      setAuditModal((prev) => ({ ...prev, loading: false, logs: res.logs || [] }))
    } catch (e) {
      setAuditModal((prev) => ({ ...prev, loading: false, error: (e as { message?: string })?.message || t.auditModal.loadError }))
    }
  }

  useEffect(() => {
    if (!auditModal.open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setAuditModal((prev) => ({ ...prev, open: false }))
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [auditModal.open])

  return (
    <div className="flex flex-col relative" style={{ height: 'calc(100vh - 130px)' }}>
      <div className="flex items-center gap-2 mb-2">
        <h1 className="text-xl font-bold">Электронный журнал</h1>
        {activeWeekMeta && (
          <span className="text-xs text-gray-600">
            Неделя: {fmtIso(activeWeekMeta.start)} — {fmtIso(activeWeekMeta.end)}
            {loadingOtherWeek && (
              <span className="ml-2 text-amber-700">— загрузка…</span>
            )}
          </span>
        )}
        <button
          onClick={() => {}}
          disabled={weekDataQ.isFetching}
          className="ml-auto hidden px-2 py-0.5 text-xs bg-white border rounded hover:bg-gray-100 disabled:opacity-50"
          title="Сейчас загрузить неделю из Google (иначе автообновление)"
        >
          {weekDataQ.isFetching ? 'Обновляю…' : 'Обновить'}
        </button>
        <div className="ml-auto relative">
          <button onClick={() => setMenuOpen((v) => !v)} className="px-2 py-0.5 text-xs bg-white border rounded hover:bg-gray-100">Меню</button>
          {menuOpen && (
            <div className="absolute right-0 mt-1 z-40 w-36 rounded border bg-white shadow">
              <button
                className="w-full text-left px-3 py-2 text-xs hover:bg-gray-50"
                onClick={() => {
                  setSearchOpen(true)
                  setMenuOpen(false)
                }}
              >
                Поиск
              </button>
            </div>
          )}
        </div>
        <button onClick={() => setSettingsOpen(true)} disabled={!activeWeek} className="px-2 py-0.5 text-xs bg-white border rounded hover:bg-gray-100 disabled:opacity-50">Настройки</button>
      </div>

      <div className="mb-2 flex items-center gap-1 text-xs">
        <span className="text-gray-600">Заливка:</span>
        {(['none', 'gray', 'yellow', 'green', 'red', 'blue'] as const).map((fill) => (
          <button
            key={fill}
            onClick={() => applyColor(fill)}
            disabled={selectedCells.size === 0}
            className="w-5 h-5 border border-gray-300 rounded disabled:opacity-40"
            style={{
              backgroundColor:
                fill === 'none' ? '#fff' :
                fill === 'gray' ? '#ededed' :
                fill === 'yellow' ? '#fff2bf' :
                fill === 'green' ? '#d7efd7' :
                fill === 'red' ? '#f7d7d7' : '#d9e8fa',
            }}
            title={fill}
          />
        ))}
        {selectedCells.size > 1 && (
          <span className="ml-1 text-blue-600">выделено: {selectedCells.size}</span>
        )}
      </div>

      {weekLoading && (
        <div className="flex-1 flex flex-col items-center justify-center gap-2 text-sm text-gray-600 border border-gray-200 rounded bg-white shadow">
          <span className="inline-block h-6 w-6 animate-spin rounded-full border-2 border-gray-300 border-t-blue-600" />
          Загрузка недели{activeWeekMeta ? ` ${fmtIso(activeWeekMeta.start)} — ${fmtIso(activeWeekMeta.end)}` : ''}…
        </div>
      )}

      {!activeWeek && !weekLoading && !weeksQ.isError && (
        <div className="flex-1 flex items-center justify-center text-sm text-gray-600 border border-gray-200 rounded bg-white p-4">
          Журнал запускается, подгружаю недели...
        </div>
      )}

      {weekDataQ.isError && !tableData && !weekLoading && (
        <div className="flex-1 flex items-center justify-center text-sm text-red-600 border border-red-200 rounded bg-red-50 p-4">
          Не удалось загрузить неделю. {(weekDataQ.error as { message?: string })?.message}
        </div>
      )}

      {tableData && (
        <div className={`relative flex-1 overflow-hidden bg-white rounded shadow border border-gray-200${loadingOtherWeek ? ' opacity-90' : ''}`}>
          <div ref={tableContainerRef} className="overflow-auto h-full">
            <table className="border-collapse text-xs" style={{ width: '100%', minWidth: tableMinWidth, tableLayout: 'fixed' }}>
              <colgroup><col style={{ width: 130 }} />{people.map((p) => <col key={p} />)}</colgroup>
              <thead>
                <tr className="sticky top-0 z-30 bg-gray-100">
                  <th className="sticky left-0 z-40 bg-gray-100 border border-gray-300 text-left px-2 py-1">Дата · Время</th>
                  {people.map((p) => <th key={p} className="border border-gray-300 px-1 py-1 text-left whitespace-normal text-[11px] leading-tight">{p}</th>)}
                </tr>
              </thead>
              <tbody>
                {tableData.days.map((day) => day.time_slots.map((time, ti) => {
                  const dayDividerClass = ti === day.time_slots.length - 1 ? 'border-b-2 border-b-gray-500' : ''
                  return (
                    <tr key={`${day.date}-${time}`} data-date={ti === 0 ? day.date : undefined}>
                      <td className={`sticky left-0 z-20 border border-gray-300 text-xs ${ti === 0 ? 'bg-blue-50 font-medium' : 'bg-gray-50'} ${dayDividerClass}`} style={{ height: 36 }}>
                        <div className="flex flex-col px-2 py-0.5 leading-tight">
                          {ti === 0 && <span className="text-[11px] font-semibold text-blue-700">{day.weekday} {fmtIso(day.date)}</span>}
                          <span className="text-[10px] text-gray-600">{time}</span>
                        </div>
                      </td>
                      {people.map((person) => {
                        const key = cellKey(day.date, time, person)
                        const cell: CellPos = { date: day.date, time, person }
                        const isSelected = selectedCells.has(key)
                        const isPrimary = lastSelectedCell ? cellKey(lastSelectedCell.date, lastSelectedCell.time, lastSelectedCell.person) === key : false
                        return (
                          <td key={person} className={`border border-gray-200 p-0 align-top relative ${dayDividerClass}`} style={{ height: 36 }}>
                            <JournalCell
                              value={tableData.values[day.date]?.[time]?.[person] ?? ''}
                              selected={isSelected && (isPrimary || selectedCells.size === 1)}
                              multiSelected={isSelected && !(isPrimary || selectedCells.size === 1)}
                              color={cellColors[key]}
                              isFirstSlot={ti === 0}
                              readOnly={!day.has_data}
                              saving={savingCellKey === key}
                              onSelect={handleCellSelect(cell)}
                              onSave={async (v) => {
                                const oldValue = tableData.values[day.date]?.[time]?.[person] ?? ''
                                await saveCell.mutateAsync({
                                  date: day.date,
                                  time,
                                  person,
                                  value: v,
                                  oldValue,
                                })
                              }}
                              onAuditClick={async () => {
                                await openAuditModal(day.date, time, person)
                              }}
                            />
                          </td>
                        )
                      })}
                    </tr>
                  )
                }))}
              </tbody>
            </table>
          </div>
        </div>
      )}
      {auditModal.open && (
        <div className="absolute inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setAuditModal((prev) => ({ ...prev, open: false }))}>
          <div className="w-[720px] max-w-[95vw] max-h-[85vh] overflow-auto rounded bg-white border shadow p-4" onClick={(e) => e.stopPropagation()}>
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm">
                <span className="font-semibold">{t.auditModal.title}:</span>{' '}
                <span className="text-base font-semibold">{fmtIso(auditModal.date)}</span>{' '}
                <span className="text-base font-semibold">{auditModal.time}</span>{' '}
                <span className="text-gray-700">· {auditModal.person}</span>
              </h2>
              <button className="text-xs border rounded px-2 py-1" onClick={() => setAuditModal((prev) => ({ ...prev, open: false }))}>{t.auditModal.close}</button>
            </div>
            {auditModal.loading && <div className="text-sm text-gray-600">{t.auditModal.loading}</div>}
            {!auditModal.loading && !!auditModal.error && <div className="text-sm text-red-600">{auditModal.error}</div>}
            {!auditModal.loading && !auditModal.error && auditModal.logs.length === 0 && <div className="text-sm text-gray-600">{t.auditModal.empty}</div>}
            {!auditModal.loading && !auditModal.error && auditModal.logs.length > 0 && <div className="space-y-2">{auditModal.logs.map((log, idx) => <div key={`${log.created_at}-${idx}`} className="rounded border border-gray-200 p-2 text-xs"><div><span className="font-semibold">{t.auditModal.who}:</span> {log.actor_name || log.actor_login || t.alerts.unknownActor}</div><div><span className="font-semibold">{t.auditModal.when}:</span> {new Date(log.created_at * 1000).toLocaleString('ru-RU')}</div><div><span className="font-semibold">{t.auditModal.oldValue}:</span> <span className="whitespace-pre-wrap">{log.old_value || '—'}</span></div><div><span className="font-semibold">{t.auditModal.newValue}:</span> <span className="whitespace-pre-wrap">{log.new_value || '—'}</span></div></div>)}</div>}
          </div>
        </div>
      )}

      {weeksQ.data && (
        <div className="mt-2 flex items-center gap-1 border-t border-gray-200 bg-gray-50 px-1 py-1 rounded-b">
          <button
            onClick={() => createNext.mutate()}
            disabled={createNext.isPending}
            className="px-3 py-1 text-xs bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50 shrink-0"
          >
            {createNext.isPending ? 'Создаю...' : '+ Следующая неделя'}
          </button>
          <div ref={tabsRef} className="flex-1 flex gap-1 overflow-x-auto scrollbar-thin">
            {orderedWeeks.map((w) => (
              <button key={w.start} data-week={w.start} onClick={() => setActiveWeek(w.start)} className={`px-2 py-1 text-xs rounded whitespace-nowrap shrink-0 transition ${activeWeek === w.start ? 'bg-blue-600 text-white' : w.contains_today ? 'bg-yellow-100 border border-yellow-400 hover:bg-yellow-200' : 'bg-white border hover:bg-gray-100'}`}>
                {w.label}{w.contains_today ? ' •' : ''}
              </button>
            ))}
          </div>
        </div>
      )}

      {settingsOpen && (
        <div className="absolute inset-0 z-50 flex items-center justify-center bg-black/30">
          <div className="w-[760px] max-w-[95vw] max-h-[90vh] overflow-auto rounded bg-white border shadow p-4">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold">Настройки недели</h2>
              <button className="text-xs border rounded px-2 py-1" onClick={() => setSettingsOpen(false)}>Закрыть</button>
            </div>
            <div className="flex flex-wrap gap-2 mb-4">
              <button className="px-2 py-1 text-xs bg-white border rounded hover:bg-gray-100" onClick={() => activeWeek && window.confirm('Сделать субботу рабочей?') && addSaturday.mutate(activeWeek)}>Суббота рабочая</button>
              <button className="px-2 py-1 text-xs bg-white border rounded hover:bg-gray-100" onClick={() => {
                if (!activeWeek) return
                const name = window.prompt('Наименование нового столбца')
                if (!name || !name.trim()) return
                addColumn.mutate({ start: activeWeek, name: name.trim() })
              }}>Добавить столбик</button>
              <button className="px-2 py-1 text-xs bg-white border rounded hover:bg-gray-100" onClick={() => {
                if (!activeWeek) return
                const name = window.prompt(`Удалить столбик (точное наименование):\n${people.join('\n')}`)
                if (!name || !name.trim()) return
                deleteColumn.mutate({ start: activeWeek, name: name.trim() })
              }}>Удалить столбик</button>
            </div>
            <div className="border rounded p-3">
              <div className="text-xs font-semibold mb-2">Изменить названия столбцов</div>
              <div className="grid grid-cols-1 gap-2">
                {people.map((p) => (
                  <div key={p} className="grid grid-cols-[1fr_1fr] gap-2 items-center">
                    <div className="text-xs text-gray-700">{p}</div>
                    <input
                      value={renameDraft[p] ?? ''}
                      onChange={(e) => setRenameDraft((prev) => ({ ...prev, [p]: e.target.value }))}
                      className="border rounded px-2 py-1 text-xs"
                      placeholder="Новое название (пусто = без изменений)"
                    />
                  </div>
                ))}
              </div>
              <div className="mt-3">
                <button className="px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700" onClick={() => {
                  if (!activeWeek) return
                  const mapping: Record<string, string> = {}
                  Object.entries(renameDraft).forEach(([from, to]) => { if (to.trim()) mapping[from] = to.trim() })
                  renameColumns.mutate({ start: activeWeek, mapping })
                }}>
                  Сохранить переименования
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {searchOpen && (
        <div className="absolute inset-0 z-50 flex items-center justify-center bg-black/30">
          <div className="w-[860px] max-w-[95vw] max-h-[90vh] overflow-auto rounded bg-white border shadow p-4">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold">Поиск по журналу</h2>
              <button className="text-xs border rounded px-2 py-1" onClick={() => setSearchOpen(false)}>Закрыть</button>
            </div>
            <div className="flex gap-2 mb-3">
              <input
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && searchQuery.trim()) searchM.mutate(searchQuery.trim())
                }}
                className="flex-1 border rounded px-2 py-1 text-sm"
                placeholder="Введите текст задачи или ФИО..."
              />
              <button
                onClick={() => searchQuery.trim() && searchM.mutate(searchQuery.trim())}
                className="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
              >
                Найти
              </button>
            </div>
            {searchM.isPending && <div className="text-sm text-gray-500">Ищу по журналу...</div>}
            {searchM.data && (
              <div className="space-y-1">
                {searchM.data.results.length === 0 && <div className="text-sm text-gray-500">Ничего не найдено</div>}
                {searchM.data.results.map((r, i) => (
                  <button
                    key={`${r.week_start}|${r.date}|${r.time}|${r.person}|${i}`}
                    className="w-full text-left border rounded p-2 hover:bg-gray-50"
                    onClick={() => {
                      setActiveWeek(r.week_start)
                      setSelectedCells(new Set([cellKey(r.date, r.time, r.person)]))
                      setLastSelectedCell({ date: r.date, time: r.time, person: r.person })
                      setSearchOpen(false)
                    }}
                  >
                    <div className="text-xs text-gray-600">{r.week_label} · {r.date} · {r.time}</div>
                    <div className="text-sm font-medium">{r.person}</div>
                    <div className="text-sm whitespace-pre-wrap">{r.value}</div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

