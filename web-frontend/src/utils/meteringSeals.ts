import type { MeteringRecord } from '../api/metering'

export type SealSlot = {
  kind: 'flowmeter' | 'temp_sensor'
  index: number
  fieldKey: keyof MeteringRecord | null
  label: string
  fromExtra: boolean
}

export function flowmeterSerialFilled(record: MeteringRecord, index: number): boolean {
  const key = `flowmeter_serial_${index}` as keyof MeteringRecord
  return String(record[key] ?? '').trim().length > 0
}

export function tempSerialFilled(record: MeteringRecord, index: number): boolean {
  const key = `temp_sensor_serial_${index}` as keyof MeteringRecord
  return String(record[key] ?? '').trim().length > 0
}

export function buildFlowmeterSealSlots(record: MeteringRecord, extraIndices: number[]): SealSlot[] {
  const slots: SealSlot[] = []
  for (let i = 1; i <= 4; i += 1) {
    if (!flowmeterSerialFilled(record, i)) continue
    slots.push({
      kind: 'flowmeter',
      index: i,
      fieldKey: `seal_flowmeter_${i}` as keyof MeteringRecord,
      label: `Пломба расходомера ${i} №`,
      fromExtra: false,
    })
  }
  extraIndices.forEach((i) => {
    if (slots.some((s) => s.kind === 'flowmeter' && s.index === i)) return
    slots.push({
      kind: 'flowmeter',
      index: i,
      fieldKey: null,
      label: `Пломба расходомера ${i} №`,
      fromExtra: true,
    })
  })
  return slots
}

export function buildTempSealSlots(record: MeteringRecord, extraIndices: number[]): SealSlot[] {
  const slots: SealSlot[] = []
  for (let i = 1; i <= 4; i += 1) {
    if (!tempSerialFilled(record, i)) continue
    slots.push({
      kind: 'temp_sensor',
      index: i,
      fieldKey: `seal_temp_sensor_${i}` as keyof MeteringRecord,
      label: `Пломба термометра ${i} №`,
      fromExtra: false,
    })
  }
  extraIndices.forEach((i) => {
    if (slots.some((s) => s.kind === 'temp_sensor' && s.index === i)) return
    slots.push({
      kind: 'temp_sensor',
      index: i,
      fieldKey: null,
      label: `Пломба термометра ${i} №`,
      fromExtra: true,
    })
  })
  return slots
}

export function nextExtraSealIndex(kind: 'flowmeter' | 'temp_sensor', record: MeteringRecord, extra: number[]): number {
  const used = new Set<number>()
  for (let i = 1; i <= 4; i += 1) {
    if (kind === 'flowmeter' && flowmeterSerialFilled(record, i)) used.add(i)
    if (kind === 'temp_sensor' && tempSerialFilled(record, i)) used.add(i)
  }
  extra.forEach((i) => used.add(i))
  let n = 1
  while (used.has(n)) n += 1
  return n
}

export const SEAL_CUT_KEYS = [
  'seal_cut_1',
  'seal_cut_2',
  'seal_cut_3',
  'seal_cut_4',
] as const
