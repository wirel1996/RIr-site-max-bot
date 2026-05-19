# План: КТПТР поиск в АРШИН по номеру "НОМЕР/НОМЕРА"

## Проблема
Парные термометры КТПТР с серийными номерами (например "6499") в АРШИН записаны как "6499/6499А". При поиске нужно пробовать этот формат первым.

## 1. Фронтенд: `web-frontend/src/components/ArshinMeterCheckModal.tsx`

После строки 51 добавить получение типа устройства из record:

```ts
  const isTempSensor = device?.serialKey === 'temp_sensor_serial_1' || device?.serialKey === 'temp_sensor_serial_2'
  const mitNotation = isTempSensor
    ? (device?.serialKey === 'temp_sensor_serial_1' ? record.temp_sensor_1 : record.temp_sensor_2)
    : undefined
```

В `search.mutationFn` (строка 60-69) добавить `mit_notation`:

```ts
  const search = useMutation({
    mutationFn: () => arshinApi.searchMeter({
      serial: editableSerial.trim(),
      result_docnum: resultDocnum.trim() || undefined,
      valid_until: validUntilFromDb || undefined,
      year: year.trim() || undefined,
      org_title: orgTitle.trim() || undefined,
      preferred_mit_notation: preferredType,
      mit_notation: mitNotation || undefined,
      serial_key: device?.serialKey,
      meter_label: device?.label,
    }),
  })
```

## 2. Бэкенд: `services/arshin_service.rb`

В `_meter_search_by_years` (строка ~391-416) после логики "г/х" (строка 408) добавить:

```ruby
    # Для КТПТР: пробуем формат "НОМЕР/НОМЕРА" первым
    if mit_notation.to_s.strip.match?(/КТПТР/i) && compact_number_for_query.match?(/\A\d+\z/)
      number_candidates.unshift("#{compact_number_for_query}/#{compact_number_for_query}А")
    end
```

## Результат
- Датчик температуры с типом "КТПТР-01" и номером "6499" → ищет "6499/6499А" первым, потом "6499", "6499 г/х" и т.д.
- Остальные приборы → как раньше, без изменений
