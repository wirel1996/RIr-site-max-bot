import type { MeteringRecord } from '../api/metering'

export type ArshinMeterDevice = {
  serialKey: keyof MeteringRecord
  dateKey: keyof MeteringRecord
  label: string
}

export const ARSHIN_METER_DEVICES: ArshinMeterDevice[] = [
  { serialKey: 'calculator_serial', dateKey: 'calculator_verification_date', label: 'Тепловычислитель' },
  { serialKey: 'flowmeter_serial_1', dateKey: 'flowmeter_verification_date_1', label: 'Расходомер 1' },
  { serialKey: 'flowmeter_serial_2', dateKey: 'flowmeter_verification_date_2', label: 'Расходомер 2' },
  { serialKey: 'temp_sensor_serial_1', dateKey: 'temp_sensor_verification_date_1', label: 'Датчик температуры 1' },
  { serialKey: 'temp_sensor_serial_2', dateKey: 'temp_sensor_verification_date_2', label: 'Датчик температуры 2' },
  { serialKey: 'pressure_sensor_serial_1', dateKey: 'pressure_sensor_verification_date_1', label: 'Датчик давления 1' },
  { serialKey: 'pressure_sensor_serial_2', dateKey: 'pressure_sensor_verification_date_2', label: 'Датчик давления 2' },
]

export function hasFailedArshinCheck(record: MeteringRecord) {
  const checks = record.arshin_checks
  if (!checks) return false
  return Object.values(checks).some((entry) => entry && entry.applicability === false)
}
