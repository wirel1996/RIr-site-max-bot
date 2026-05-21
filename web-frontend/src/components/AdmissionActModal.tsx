import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useEffect, useMemo, useState } from 'react'
import { meteringApi, type MeteringRecord, type SubmitActPayload } from '../api/metering'
import { meteringRu as t } from '../locales/ru/metering'
import { todayRu } from '../utils/meteringDates'
import {
  SEAL_CUT_KEYS,
  buildFlowmeterSealSlots,
  buildTempSealSlots,
  nextExtraSealIndex,
} from '../utils/meteringSeals'

type ActNumberMode = 'auto' | 'manual' | 'start_from'

type Props = {
  open: boolean
  category: string
  recordId: number
  record: MeteringRecord
  onClose: () => void
}

function str(v: unknown): string {
  return v === null || v === undefined ? '' : String(v)
}

export default function AdmissionActModal({ open, category, recordId, record, onClose }: Props) {
  const queryClient = useQueryClient()
  const isGspo = category === 'gspo'

  const [dateInput, setDateInput] = useState('')
  const [commercialAccounting, setCommercialAccounting] = useState('')
  const [admitUntil, setAdmitUntil] = useState('')
  const [dateOutput, setDateOutput] = useState('')
  const [outputReason, setOutputReason] = useState('')
  const [actPrimary, setActPrimary] = useState('')
  const [actPeriodic, setActPeriodic] = useState('')
  const [registrationDate, setRegistrationDate] = useState('')
  const [violations, setViolations] = useState('')
  const [project, setProject] = useState('')
  const [primaryMode, setPrimaryMode] = useState<ActNumberMode>('auto')
  const [periodicMode, setPeriodicMode] = useState<ActNumberMode>('auto')
  const [primaryStartFrom, setPrimaryStartFrom] = useState('1')
  const [periodicStartFrom, setPeriodicStartFrom] = useState('1')

  const [sealCalculator, setSealCalculator] = useState('')
  const [sealCuts, setSealCuts] = useState<Record<string, string>>({})
  const [sealValues, setSealValues] = useState<Record<string, string>>({})
  const [extraFlowmeter, setExtraFlowmeter] = useState<number[]>([])
  const [extraTemp, setExtraTemp] = useState<number[]>([])
  const [extraSealValues, setExtraSealValues] = useState<{
    flowmeter: Record<string, string>
    temp_sensor: Record<string, string>
  }>({ flowmeter: {}, temp_sensor: {} })

  const [readingsDate, setReadingsDate] = useState('')
  const [readingQ, setReadingQ] = useState('')
  const [readingM1, setReadingM1] = useState('')
  const [readingV1, setReadingV1] = useState('')
  const [readingM2, setReadingM2] = useState('')
  const [readingV2, setReadingV2] = useState('')
  const [readingT1, setReadingT1] = useState('')
  const [readingT2, setReadingT2] = useState('')
  const [readingP1, setReadingP1] = useState('')
  const [readingP2, setReadingP2] = useState('')
  const [acceptedBy, setAcceptedBy] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    if (!open) return
    setDateInput(str(record.date_input_uute))
    setCommercialAccounting(str(record.commercial_accounting))
    setAdmitUntil(str(record.admit_until) || str(record.nearest_verification_date))
    setDateOutput(str(record.date_output_uute))
    setOutputReason(str(record.output_reason))
    setActPrimary(str(record.act_primary_number))
    setActPeriodic(str(record.act_periodic_number))
    setRegistrationDate(str(record.registration_date) || todayRu())
    setViolations(str(record.violations))
    setProject(str(record.project))
    setPrimaryMode(isGspo && !record.act_primary_number ? 'auto' : 'manual')
    setPeriodicMode(isGspo && !record.act_periodic_number ? 'auto' : 'manual')
    setSealCalculator(str(record.seal_calculator))
    const cuts: Record<string, string> = {}
    SEAL_CUT_KEYS.forEach((k) => {
      cuts[k] = str(record[k])
    })
    setSealCuts(cuts)
    const seals: Record<string, string> = {}
    for (let i = 1; i <= 4; i += 1) {
      seals[`seal_flowmeter_${i}`] = str(record[`seal_flowmeter_${i}` as keyof MeteringRecord])
      seals[`seal_temp_sensor_${i}`] = str(record[`seal_temp_sensor_${i}` as keyof MeteringRecord])
    }
    setSealValues(seals)
    const extraF: number[] = []
    const extraT: number[] = []
    Object.keys(record.extra_seals?.flowmeter ?? {}).forEach((k) => {
      const n = Number(k)
      if (n > 4) extraF.push(n)
    })
    Object.keys(record.extra_seals?.temp_sensor ?? {}).forEach((k) => {
      const n = Number(k)
      if (n > 4) extraT.push(n)
    })
    setExtraFlowmeter(extraF)
    setExtraTemp(extraT)
    setExtraSealValues({
      flowmeter: { ...(record.extra_seals?.flowmeter ?? {}) },
      temp_sensor: { ...(record.extra_seals?.temp_sensor ?? {}) },
    })
    setReadingsDate(str(record.readings_date))
    setReadingQ(str(record.reading_q))
    setReadingM1(str(record.reading_m1))
    setReadingV1(str(record.reading_v1))
    setReadingM2(str(record.reading_m2))
    setReadingV2(str(record.reading_v2))
    setReadingT1(str(record.reading_t1))
    setReadingT2(str(record.reading_t2))
    setReadingP1(str(record.reading_p1))
    setReadingP2(str(record.reading_p2))
    setAcceptedBy(str(record.accepted_by))
    setError('')
  }, [open, record, isGspo])

  const flowSlots = useMemo(
    () => buildFlowmeterSealSlots(record, extraFlowmeter),
    [record, extraFlowmeter],
  )
  const tempSlots = useMemo(
    () => buildTempSealSlots(record, extraTemp),
    [record, extraTemp],
  )

  const submitMutation = useMutation({
    mutationFn: () => {
      const payload: SubmitActPayload = {
        date_input_uute: dateInput.trim(),
        commercial_accounting: commercialAccounting.trim(),
        admit_until: admitUntil.trim(),
        date_output_uute: dateOutput.trim(),
        output_reason: outputReason.trim(),
        registration_date: registrationDate.trim(),
        violations: violations.trim(),
        project: project.trim(),
        seal_calculator: sealCalculator.trim(),
        readings_date: readingsDate.trim(),
        reading_q: readingQ.trim(),
        reading_m1: readingM1.trim(),
        reading_v1: readingV1.trim(),
        reading_m2: readingM2.trim(),
        reading_v2: readingV2.trim(),
        reading_t1: readingT1.trim(),
        reading_t2: readingT2.trim(),
        reading_p1: readingP1.trim(),
        reading_p2: readingP2.trim(),
        accepted_by: acceptedBy.trim(),
        extra_seals: extraSealValues,
        extra_flowmeter_indices: extraFlowmeter,
        extra_temp_indices: extraTemp,
      }
      SEAL_CUT_KEYS.forEach((k) => {
        payload[k] = sealCuts[k]?.trim() ?? ''
      })
      const payloadRecord = payload as Record<string, unknown>
      for (let i = 1; i <= 4; i += 1) {
        payloadRecord[`seal_flowmeter_${i}`] = sealValues[`seal_flowmeter_${i}`]?.trim() ?? ''
        payloadRecord[`seal_temp_sensor_${i}`] = sealValues[`seal_temp_sensor_${i}`]?.trim() ?? ''
      }
      if (isGspo) {
        payload.act_primary_mode = primaryMode
        payload.act_periodic_mode = periodicMode
        if (primaryMode === 'manual') payload.act_primary_number = actPrimary.trim()
        if (periodicMode === 'manual') payload.act_periodic_number = actPeriodic.trim()
        if (primaryMode === 'start_from') payload.act_primary_start_from = Number(primaryStartFrom) || 1
        if (periodicMode === 'start_from') payload.act_periodic_start_from = Number(periodicStartFrom) || 1
      } else {
        payload.act_primary_number = actPrimary.trim()
        payload.act_periodic_number = actPeriodic.trim()
      }
      return meteringApi.submitAct(category, recordId, payload)
    },
    onSuccess: (updated) => {
      queryClient.setQueryData(['metering', category, 'detail', String(recordId)], updated)
      queryClient.invalidateQueries({ queryKey: ['metering', category] })
      onClose()
    },
    onError: (e) => setError((e as Error).message || t.detail.submitActFailed),
  })

  const validateClient = (): string | null => {
    if (!dateInput.trim()) return `${t.detail.requiredField}: Дата ввода УУТЭ`
    if (!commercialAccounting.trim()) return `${t.detail.requiredField}: Введен в коммерческий учет`
    if (!sealCalculator.trim()) return `${t.detail.requiredField}: Пломба вычислителя №`
    for (const slot of flowSlots) {
      const v = slot.fromExtra
        ? extraSealValues.flowmeter[String(slot.index)]
        : sealValues[`seal_flowmeter_${slot.index}`]
      if (!v?.trim()) return `${t.detail.requiredField}: ${slot.label}`
    }
    for (const slot of tempSlots) {
      const v = slot.fromExtra
        ? extraSealValues.temp_sensor[String(slot.index)]
        : sealValues[`seal_temp_sensor_${slot.index}`]
      if (!v?.trim()) return `${t.detail.requiredField}: ${slot.label}`
    }
    return null
  }

  if (!open) return null

  const renderActNumberBlock = (
    title: string,
    value: string,
    setValue: (v: string) => void,
    mode: ActNumberMode,
    setMode: (m: ActNumberMode) => void,
    startFrom: string,
    setStartFrom: (v: string) => void,
  ) => (
    <div className="rounded border bg-gray-50 p-2 space-y-2">
      <p className="text-xs font-medium text-gray-700">{title}</p>
      {isGspo && (
        <div className="flex flex-wrap gap-2 text-xs">
          <label className="flex items-center gap-1">
            <input type="radio" checked={mode === 'auto'} onChange={() => setMode('auto')} />
            {t.detail.actNumberAuto}
          </label>
          <label className="flex items-center gap-1">
            <input type="radio" checked={mode === 'manual'} onChange={() => setMode('manual')} />
            {t.detail.actNumberManual}
          </label>
          <label className="flex items-center gap-1">
            <input type="radio" checked={mode === 'start_from'} onChange={() => setMode('start_from')} />
            {t.detail.actNumberStartFrom}
          </label>
          {mode === 'start_from' && (
            <input
              type="number"
              min={1}
              value={startFrom}
              onChange={(e) => setStartFrom(e.target.value)}
              className="w-16 rounded border px-1 py-0.5"
            />
          )}
        </div>
      )}
      {(mode === 'manual' || !isGspo) && (
        <input
          value={value}
          onChange={(e) => setValue(e.target.value)}
          className="w-full rounded border px-2 py-1 text-sm"
        />
      )}
      {isGspo && mode === 'auto' && (
        <p className="text-xs text-gray-500">Номер будет присвоен автоматически при сохранении</p>
      )}
    </div>
  )

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <div className="my-4 w-full max-w-2xl rounded-lg bg-white shadow-lg">
        <div className="sticky top-0 z-10 flex items-center justify-between border-b bg-white px-4 py-3">
          <h2 className="font-semibold">{t.detail.actModalTitle}</h2>
          <button type="button" onClick={onClose} className="rounded border px-2 py-1 text-sm">
            {t.detail.cancel}
          </button>
        </div>
        <form
          className="space-y-4 p-4"
          onSubmit={(e) => {
            e.preventDefault()
            const err = validateClient()
            if (err) {
              setError(err)
              return
            }
            submitMutation.mutate()
          }}
        >
          <section>
            <h3 className="mb-2 text-sm font-semibold">Акты и допуск</h3>
            <div className="grid gap-2 sm:grid-cols-2">
              <label className="text-xs">
                Дата ввода УУТЭ *
                <input value={dateInput} onChange={(e) => setDateInput(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" placeholder="ДД.ММ.ГГГГ" />
              </label>
              <label className="text-xs">
                Введен в коммерческий учет *
                <select value={commercialAccounting} onChange={(e) => setCommercialAccounting(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm">
                  <option value="">—</option>
                  <option value="да">{t.detail.yes}</option>
                  <option value="нет">{t.detail.no}</option>
                </select>
              </label>
              <label className="text-xs">
                Допуск до
                <input value={admitUntil} onChange={(e) => setAdmitUntil(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              <label className="text-xs">
                Дата вывода УУТЭ
                <input value={dateOutput} onChange={(e) => setDateOutput(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              <label className="text-xs sm:col-span-2">
                Причина вывода
                <input value={outputReason} onChange={(e) => setOutputReason(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              <label className="text-xs">
                Дата регистрации
                <input value={registrationDate} onChange={(e) => setRegistrationDate(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              <label className="text-xs">
                Проект
                <input value={project} onChange={(e) => setProject(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              <label className="text-xs sm:col-span-2">
                Нарушения
                <input value={violations} onChange={(e) => setViolations(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
            </div>
            <div className="mt-2 grid gap-2 sm:grid-cols-2">
              {renderActNumberBlock(
                '№ акта ввода',
                actPrimary,
                setActPrimary,
                primaryMode,
                setPrimaryMode,
                primaryStartFrom,
                setPrimaryStartFrom,
              )}
              {renderActNumberBlock(
                '№ акта периодической проверки',
                actPeriodic,
                setActPeriodic,
                periodicMode,
                setPeriodicMode,
                periodicStartFrom,
                setPeriodicStartFrom,
              )}
            </div>
          </section>

          <section>
            <h3 className="mb-2 text-sm font-semibold">Пломбы</h3>
            <label className="mb-2 block text-xs">
              Пломба вычислителя № *
              <input value={sealCalculator} onChange={(e) => setSealCalculator(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
            </label>
            {flowSlots.map((slot) => (
              <label key={`f-${slot.index}`} className="mb-2 block text-xs">
                {slot.label} *
                <input
                  value={
                    slot.fromExtra
                      ? extraSealValues.flowmeter[String(slot.index)] ?? ''
                      : sealValues[`seal_flowmeter_${slot.index}`] ?? ''
                  }
                  onChange={(e) => {
                    if (slot.fromExtra) {
                      setExtraSealValues((cur) => ({
                        ...cur,
                        flowmeter: { ...cur.flowmeter, [String(slot.index)]: e.target.value },
                      }))
                    } else {
                      setSealValues((cur) => ({ ...cur, [`seal_flowmeter_${slot.index}`]: e.target.value }))
                    }
                  }}
                  className="mt-0.5 w-full rounded border px-2 py-1 text-sm"
                />
              </label>
            ))}
            <button
              type="button"
              className="mb-2 text-xs text-blue-700 hover:underline"
              onClick={() => {
                const n = nextExtraSealIndex('flowmeter', record, extraFlowmeter)
                setExtraFlowmeter((cur) => [...cur, n])
              }}
            >
              {t.detail.addFlowmeterSeal}
            </button>
            {tempSlots.map((slot) => (
              <label key={`t-${slot.index}`} className="mb-2 block text-xs">
                {slot.label} *
                <input
                  value={
                    slot.fromExtra
                      ? extraSealValues.temp_sensor[String(slot.index)] ?? ''
                      : sealValues[`seal_temp_sensor_${slot.index}`] ?? ''
                  }
                  onChange={(e) => {
                    if (slot.fromExtra) {
                      setExtraSealValues((cur) => ({
                        ...cur,
                        temp_sensor: { ...cur.temp_sensor, [String(slot.index)]: e.target.value },
                      }))
                    } else {
                      setSealValues((cur) => ({ ...cur, [`seal_temp_sensor_${slot.index}`]: e.target.value }))
                    }
                  }}
                  className="mt-0.5 w-full rounded border px-2 py-1 text-sm"
                />
              </label>
            ))}
            <button
              type="button"
              className="mb-2 text-xs text-blue-700 hover:underline"
              onClick={() => {
                const n = nextExtraSealIndex('temp_sensor', record, extraTemp)
                setExtraTemp((cur) => [...cur, n])
              }}
            >
              {t.detail.addTempSeal}
            </button>
            <div className="grid gap-2 sm:grid-cols-2">
              {SEAL_CUT_KEYS.map((k, idx) => (
                <label key={k} className="text-xs">
                  Пломба врезки №{idx + 1}
                  <input
                    value={sealCuts[k] ?? ''}
                    onChange={(e) => setSealCuts((cur) => ({ ...cur, [k]: e.target.value }))}
                    className="mt-0.5 w-full rounded border px-2 py-1 text-sm"
                  />
                </label>
              ))}
            </div>
          </section>

          <section>
            <h3 className="mb-2 text-sm font-semibold">Показания</h3>
            <div className="grid gap-2 sm:grid-cols-2">
              <label className="text-xs">
                Дата показаний
                <input value={readingsDate} onChange={(e) => setReadingsDate(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              <label className="text-xs">
                Q
                <input value={readingQ} onChange={(e) => setReadingQ(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              {(
                [
                  ['M1', readingM1, setReadingM1],
                  ['V1', readingV1, setReadingV1],
                  ['M2', readingM2, setReadingM2],
                  ['V2', readingV2, setReadingV2],
                  ['t1', readingT1, setReadingT1],
                  ['t2', readingT2, setReadingT2],
                  ['P1', readingP1, setReadingP1],
                  ['P2', readingP2, setReadingP2],
                ] as const
              ).map(([label, val, setVal]) => (
                <label key={label} className="text-xs">
                  {label}
                  <input value={val} onChange={(e) => setVal(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
                </label>
              ))}
              <label className="text-xs sm:col-span-2">
                Принял
                <input
                  value={acceptedBy}
                  onChange={(e) => setAcceptedBy(e.target.value)}
                  className="mt-0.5 w-full rounded border px-2 py-1 text-sm"
                />
              </label>
            </div>
          </section>

          {(error || submitMutation.error) && (
            <div className="rounded border border-red-200 bg-red-50 p-2 text-sm text-red-800">
              {error || t.detail.submitActFailed}
            </div>
          )}

          <div className="flex justify-end gap-2 border-t pt-3">
            <button type="button" onClick={onClose} className="rounded border px-3 py-1.5 text-sm">
              {t.detail.cancel}
            </button>
            <button
              type="submit"
              disabled={submitMutation.isPending}
              className="rounded bg-blue-600 px-4 py-1.5 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
            >
              {submitMutation.isPending ? t.detail.saving : t.detail.submitAct}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
