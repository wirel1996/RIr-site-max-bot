import type { MeteringRecord } from '../api/metering'

type SerialKey = keyof MeteringRecord

function hasPulsar(value: unknown) {
  return String(value ?? '').toLowerCase().includes('пульсар')
}

function digitsOnly(value: unknown) {
  return String(value ?? '').replace(/\D+/g, '')
}

function padPulsarSerial(value: unknown) {
  const digits = digitsOnly(value)
  if (!digits) return ''
  if (digits.length === 7) return `0${digits}`
  return digits
}

function unique(values: string[]) {
  return values.map((value) => value.trim()).filter(Boolean).filter((value, index, arr) => arr.indexOf(value) === index)
}

export function buildArshinSerialCandidates(record: MeteringRecord, serialKey?: SerialKey | string | null) {
  const key = String(serialKey ?? '')
  const currentSerial = String(record[key as keyof MeteringRecord] ?? '').trim()
  if (!currentSerial) return []

  const deviceIsPulsar =
    (key === 'calculator_serial' && hasPulsar(record.calculator_type))
    || (key === 'flowmeter_serial_1' && hasPulsar(record.flowmeter_1))
    || (key === 'flowmeter_serial_2' && hasPulsar(record.flowmeter_2))

  const cardHasPulsar = hasPulsar(record.calculator_type) || hasPulsar(record.flowmeter_1) || hasPulsar(record.flowmeter_2)
  const isPulsarSearch = deviceIsPulsar || (key === 'calculator_serial' && cardHasPulsar)
  if (!isPulsarSearch) return []

  const flow1 = padPulsarSerial(record.flowmeter_serial_1)
  const flow2 = padPulsarSerial(record.flowmeter_serial_2)
  const current = padPulsarSerial(currentSerial)
  const candidates: string[] = []

  if (flow1 && flow2) candidates.push(`${flow1}/${flow2}`)
  if (current) candidates.push(current)
  candidates.push(currentSerial)

  return unique(candidates)
}
