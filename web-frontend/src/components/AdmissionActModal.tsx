import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useEffect, useMemo, useState } from 'react'
import { meteringApi, type ActKind, type MeteringRecord, type SubmitActPayload } from '../api/metering'
import { meteringRu as t } from '../locales/ru/metering'
import { todayRu } from '../utils/meteringDates'
import {
  SEAL_CUT_KEYS,
  buildFlowmeterSealSlots,
  buildTempSealSlots,
  nextExtraSealIndex,
} from '../utils/meteringSeals'

type Props = {
  open: boolean
  kind: ActKind
  category: string
  recordId: number
  record: MeteringRecord
  onClose: () => void
}

function str(v: unknown): string {
  return v === null || v === undefined ? '' : String(v)
}

function ReadingsFields({
  readingsDate,
  setReadingsDate,
  readingQ,
  setReadingQ,
  readingM1,
  setReadingM1,
  readingV1,
  setReadingV1,
  readingM2,
  setReadingM2,
  readingV2,
  setReadingV2,
  readingT1,
  setReadingT1,
  readingT2,
  setReadingT2,
  readingP1,
  setReadingP1,
  readingP2,
  setReadingP2,
  showAccepted,
  acceptedBy,
  setAcceptedBy,
}: {
  readingsDate: string
  setReadingsDate: (v: string) => void
  readingQ: string
  setReadingQ: (v: string) => void
  readingM1: string
  setReadingM1: (v: string) => void
  readingV1: string
  setReadingV1: (v: string) => void
  readingM2: string
  setReadingM2: (v: string) => void
  readingV2: string
  setReadingV2: (v: string) => void
  readingT1: string
  setReadingT1: (v: string) => void
  readingT2: string
  setReadingT2: (v: string) => void
  readingP1: string
  setReadingP1: (v: string) => void
  readingP2: string
  setReadingP2: (v: string) => void
  showAccepted?: boolean
  acceptedBy?: string
  setAcceptedBy?: (v: string) => void
}) {
  return (
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
      {showAccepted && setAcceptedBy && (
        <label className="text-xs sm:col-span-2">
          Принял
          <input value={acceptedBy ?? ''} onChange={(e) => setAcceptedBy(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
        </label>
      )}
    </div>
  )
}

export default function AdmissionActModal({ open, kind, category, recordId, record, onClose }: Props) {
  const queryClient = useQueryClient()
  const isInput = kind === 'input'
  const isCheck = kind === 'check'
  const isOutput = kind === 'output'

  const [dateInput, setDateInput] = useState('')
  const [commercialAccounting, setCommercialAccounting] = useState('')
  const [dateOutput, setDateOutput] = useState('')
  const [outputReason, setOutputReason] = useState('')
  const [registrationDate, setRegistrationDate] = useState('')
  const [violations, setViolations] = useState('')
  const [project, setProject] = useState('')
  const [checkDate, setCheckDate] = useState('')
  const [checkViolations, setCheckViolations] = useState('')
  const [checkNote, setCheckNote] = useState('')

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
    setDateOutput(str(record.date_output_uute))
    setOutputReason(str(record.output_reason))
    setRegistrationDate(str(record.registration_date) || todayRu())
    setViolations(str(record.violations))
    setProject(str(record.project))
    setCheckDate(str(record.check_date))
    setCheckViolations(str(record.check_violations))
    setCheckNote(str(record.check_note))
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
  }, [open, record])

  const flowSlots = useMemo(
    () => buildFlowmeterSealSlots(record, extraFlowmeter),
    [record, extraFlowmeter],
  )
  const tempSlots = useMemo(
    () => buildTempSealSlots(record, extraTemp),
    [record, extraTemp],
  )

  const removeExtraFlowmeter = (index: number) => {
    setExtraFlowmeter((cur) => cur.filter((i) => i !== index))
    setExtraSealValues((cur) => {
      const flowmeter = { ...cur.flowmeter }
      delete flowmeter[String(index)]
      return { ...cur, flowmeter }
    })
  }

  const removeExtraTemp = (index: number) => {
    setExtraTemp((cur) => cur.filter((i) => i !== index))
    setExtraSealValues((cur) => {
      const temp_sensor = { ...cur.temp_sensor }
      delete temp_sensor[String(index)]
      return { ...cur, temp_sensor }
    })
  }

  const appendReadings = (payload: SubmitActPayload) => {
    payload.readings_date = readingsDate.trim()
    payload.reading_q = readingQ.trim()
    payload.reading_m1 = readingM1.trim()
    payload.reading_v1 = readingV1.trim()
    payload.reading_m2 = readingM2.trim()
    payload.reading_v2 = readingV2.trim()
    payload.reading_t1 = readingT1.trim()
    payload.reading_t2 = readingT2.trim()
    payload.reading_p1 = readingP1.trim()
    payload.reading_p2 = readingP2.trim()
  }

  const submitMutation = useMutation({
    mutationFn: () => {
      const payload: SubmitActPayload = { act_kind: kind }
      if (isInput) {
        payload.date_input_uute = dateInput.trim()
        payload.registration_date = registrationDate.trim()
        payload.violations = violations.trim()
        payload.project = project.trim()
        payload.seal_calculator = sealCalculator.trim()
        payload.extra_seals = extraSealValues
        payload.extra_flowmeter_indices = extraFlowmeter
        payload.extra_temp_indices = extraTemp
        SEAL_CUT_KEYS.forEach((k) => {
          payload[k] = sealCuts[k]?.trim() ?? ''
        })
        const payloadRecord = payload as Record<string, unknown>
        for (let i = 1; i <= 4; i += 1) {
          payloadRecord[`seal_flowmeter_${i}`] = sealValues[`seal_flowmeter_${i}`]?.trim() ?? ''
          payloadRecord[`seal_temp_sensor_${i}`] = sealValues[`seal_temp_sensor_${i}`]?.trim() ?? ''
        }
        appendReadings(payload)
      } else if (isCheck) {
        payload.check_date = checkDate.trim()
        payload.check_violations = checkViolations.trim()
        payload.check_note = checkNote.trim()
        appendReadings(payload)
      } else {
        payload.date_output_uute = dateOutput.trim()
        payload.output_reason = outputReason.trim()
        payload.commercial_accounting = commercialAccounting.trim()
        payload.accepted_by = acceptedBy.trim()
        appendReadings(payload)
      }
      return meteringApi.submitAct(category, recordId, payload)
    },
    onSuccess: (updated) => {
      queryClient.setQueryData(['metering', category, 'detail', String(recordId)], updated)
      queryClient.invalidateQueries({ queryKey: ['metering', category] })
      void queryClient.refetchQueries({ queryKey: ['metering', category, 'act-history', String(recordId)] })
      queryClient.invalidateQueries({ queryKey: ['metering', category, 'block-history'] })
      onClose()
    },
    onError: (e) => setError((e as Error).message || t.detail.submitActFailed),
  })

  const validateClient = (): string | null => {
    if (isCheck) {
      if (!checkDate.trim()) return `${t.detail.requiredField}: Дата проверки`
      return null
    }
    if (isOutput) {
      if (!dateOutput.trim()) return `${t.detail.requiredField}: Дата вывода УУТЭ`
      return null
    }
    if (!dateInput.trim()) return `${t.detail.requiredField}: Дата ввода УУТЭ`
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

  const modalTitle = isInput
    ? t.detail.actModalTitleInput
    : isCheck
      ? t.detail.actModalTitleCheck
      : t.detail.actModalTitleOutput

  const submitLabel = isInput
    ? t.detail.submitActInput
    : isCheck
      ? t.detail.submitActCheck
      : t.detail.submitActOutput

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4">
      <div className="my-4 w-full max-w-2xl rounded-lg bg-white shadow-lg">
        <div className="sticky top-0 z-10 flex items-center justify-between border-b bg-white px-4 py-3">
          <h2 className="font-semibold">{modalTitle}</h2>
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
          <p className="text-xs text-gray-600">{t.detail.actNumberAutoHint}</p>

          {isInput && (
            <section>
              <h3 className="mb-2 text-sm font-semibold">Акт ввода</h3>
              <p className="mb-2 text-xs text-gray-600">
                {t.detail.admitUntilPreviewInput}
                {record.nearest_verification_date ? ` (${String(record.nearest_verification_date)})` : ''}
              </p>
              <div className="grid gap-2 sm:grid-cols-2">
                <label className="text-xs">
                  Дата ввода УУТЭ *
                  <input value={dateInput} onChange={(e) => setDateInput(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" placeholder="ДД.ММ.ГГГГ" />
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
            </section>
          )}

          {isCheck && (
            <section>
              <h3 className="mb-2 text-sm font-semibold">Последняя проверка</h3>
              <div className="grid gap-2 sm:grid-cols-2">
                <label className="text-xs">
                  Дата проверки *
                  <input value={checkDate} onChange={(e) => setCheckDate(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" placeholder="ДД.ММ.ГГГГ" />
                </label>
                <label className="text-xs sm:col-span-2">
                  Нарушения
                  <input value={checkViolations} onChange={(e) => setCheckViolations(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
                </label>
                <label className="text-xs sm:col-span-2">
                  Примечания
                  <input value={checkNote} onChange={(e) => setCheckNote(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
                </label>
              </div>
            </section>
          )}

          {isOutput && (
            <section>
              <h3 className="mb-2 text-sm font-semibold">Акт вывода</h3>
              <p className="mb-2 text-xs text-gray-600">
                {t.detail.admitUntilPreviewOutput}
                {dateOutput.trim() ? `: ${dateOutput.trim()}` : ''}
              </p>
              <div className="grid gap-2 sm:grid-cols-2">
                <label className="text-xs">
                  Дата вывода УУТЭ *
                  <input value={dateOutput} onChange={(e) => setDateOutput(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" placeholder="ДД.ММ.ГГГГ" />
                </label>
                <label className="text-xs">
                  Введен в коммерческий учет
                  <select value={commercialAccounting} onChange={(e) => setCommercialAccounting(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm">
                    <option value="">—</option>
                    <option value="да">{t.detail.yes}</option>
                    <option value="нет">{t.detail.no}</option>
                  </select>
                </label>
                <label className="text-xs sm:col-span-2">
                  Причина вывода
                  <input value={outputReason} onChange={(e) => setOutputReason(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
                </label>
              </div>
            </section>
          )}

          {isInput && (
            <section>
              <h3 className="mb-2 text-sm font-semibold">Пломбы</h3>
              <label className="mb-2 block text-xs">
                Пломба вычислителя № *
                <input value={sealCalculator} onChange={(e) => setSealCalculator(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1 text-sm" />
              </label>
              {flowSlots.map((slot) => (
                <div key={`f-${slot.index}`} className="mb-2">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs">
                      {slot.label} *
                    </span>
                    {slot.fromExtra && (
                      <button
                        type="button"
                        className="shrink-0 text-xs text-red-700 hover:underline"
                        onClick={() => removeExtraFlowmeter(slot.index)}
                      >
                        {t.detail.removeExtraSeal}
                      </button>
                    )}
                  </div>
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
                </div>
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
                <div key={`t-${slot.index}`} className="mb-2">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs">
                      {slot.label} *
                    </span>
                    {slot.fromExtra && (
                      <button
                        type="button"
                        className="shrink-0 text-xs text-red-700 hover:underline"
                        onClick={() => removeExtraTemp(slot.index)}
                      >
                        {t.detail.removeExtraSeal}
                      </button>
                    )}
                  </div>
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
                </div>
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
          )}

          {(isInput || isCheck || isOutput) && (
            <section>
              <h3 className="mb-2 text-sm font-semibold">Показания</h3>
              <ReadingsFields
                readingsDate={readingsDate}
                setReadingsDate={setReadingsDate}
                readingQ={readingQ}
                setReadingQ={setReadingQ}
                readingM1={readingM1}
                setReadingM1={setReadingM1}
                readingV1={readingV1}
                setReadingV1={setReadingV1}
                readingM2={readingM2}
                setReadingM2={setReadingM2}
                readingV2={readingV2}
                setReadingV2={setReadingV2}
                readingT1={readingT1}
                setReadingT1={setReadingT1}
                readingT2={readingT2}
                setReadingT2={setReadingT2}
                readingP1={readingP1}
                setReadingP1={setReadingP1}
                readingP2={readingP2}
                setReadingP2={setReadingP2}
                showAccepted={isOutput}
                acceptedBy={acceptedBy}
                setAcceptedBy={setAcceptedBy}
              />
            </section>
          )}

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
              {submitMutation.isPending ? t.detail.saving : submitLabel}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
