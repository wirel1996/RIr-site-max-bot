# План: MBS приоритеты + предложение изменить номер датчика давления

## 1. Обновить пул приоритетов датчиков давления

**Файл:** `services/arshin_type_priority.rb`, строка 20

**Заменить:**
```ruby
    'pressure_sensor' => []
```

**На:**
```ruby
    'pressure_sensor' => ['MBS 1700', 'MBS 1750', 'MBS 3000', 'MBS 3050', 'MBS 33', 'MBS 3200', 'MBS 3250', 'MBS 4510']
```

## 2. Добавить serial_mismatch в apply_arshin_meter_check

**Файл:** `services/uute_service.rb`, метод `apply_arshin_meter_check` (строка 278)

**После строки 286** (`raise ArgumentError, 'uute not found' unless row`) добавить:

```ruby
    db_serial = row[key].to_s.strip
    arshin_serial = item['mi_number'].to_s.strip
    serial_mismatch = nil
    if !db_serial.empty? && !arshin_serial.empty? && db_serial != arshin_serial
      serial_mismatch = { 'serial_key' => key, 'current' => db_serial, 'found' => arshin_serial }
    end
```

**В возвращаемом хэше** (строки 363-368) добавить `serial_mismatch`:

```ruby
    {
      record: record,
      applicability: applicable,
      yadisk_path: yadisk_path,
      pdf_error: pdf_error,
      serial_mismatch: serial_mismatch
    }
```

## 3. Добавить тип serial_mismatch в API response

**Файл:** `web-frontend/src/api/arshin.ts`

**Добавить в `ArshinMeterApplyResponse`** (строка 52):

```typescript
export type ArshinMeterApplyResponse = {
  record: MeteringRecord
  applicability: boolean
  yadisk_path: string | null
  pdf_error: string | null
  serial_mismatch?: {
    serial_key: string
    current: string
    found: string
  } | null
}
```

## 4. Добавить диалог обновления номера в ArshinMeterCheckModal

**Файл:** `web-frontend/src/components/ArshinMeterCheckModal.tsx`

### 4.1. Добавить состояние для диалога

**После строки 40** (`const [message, setMessage] = useState('')`) добавить:

```typescript
  const [serialMismatch, setSerialMismatch] = useState<{
    serial_key: string
    current: string
    found: string
  } | null>(null)
```

### 4.2. Обработать serial_mismatch в onSuccess мутации apply

**Заменить блок `onSuccess`** (строки 84-97):

```typescript
    onSuccess: (result, item) => {
      queryClient.setQueryData(['metering', 'detail', String(uuteId)], result.record)
      queryClient.invalidateQueries({ queryKey: ['metering', 'gspo'] })

      if (item?.mit_notation && device) {
        savePreferredMitNotation(device.serialKey, item.mit_notation)
      }

      if (result.serial_mismatch) {
        setSerialMismatch(result.serial_mismatch)
      }

      const parts = ['Данные из АРШИН сохранены в карточку.']
      if (result.yadisk_path) parts.push(`PDF: ${result.yadisk_path}`)
      if (result.pdf_error) parts.push(`PDF: ${result.pdf_error}`)
      setMessage(parts.join(' '))
    },
```

### 4.3. Добавить функцию обновления номера

**После `runSearch`** (строка 106) добавить:

```typescript
  const updateSerial = () => {
    if (!serialMismatch) return
    const field = serialMismatch.serial_key
    fetch(`/api/metering/gspo/${uuteId}`, {
      method: 'PATCH',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ [field]: serialMismatch.found }),
    })
      .then((res) => {
        if (!res.ok) throw new Error('Не удалось обновить номер')
        return res.json()
      })
      .then(() => {
        queryClient.invalidateQueries({ queryKey: ['metering', 'detail', String(uuteId)] })
        queryClient.invalidateQueries({ queryKey: ['metering', 'gspo'] })
        setEditableSerial(serialMismatch.found)
        setMessage(`Номер обновлён: ${serialMismatch.current} → ${serialMismatch.found}`)
        setSerialMismatch(null)
      })
      .catch((err: Error) => setMessage(err.message))
  }
```

### 4.4. Добавить UI диалога в JSX

**Перед закрывающим `</div>` модального окна** (перед строкой 258, после блока с результатами поиска) добавить:

```tsx
          {serialMismatch && (
            <div className="rounded border border-amber-300 bg-amber-50 p-4">
              <p className="text-sm font-medium text-amber-900">
                Номер в АРШИН отличается от номера в базе
              </p>
              <p className="mt-1 text-sm text-amber-800">
                В базе: <strong>{serialMismatch.current}</strong>
                {' '}→ В АРШИН: <strong>{serialMismatch.found}</strong>
              </p>
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  onClick={updateSerial}
                  className="rounded bg-amber-600 px-3 py-1.5 text-sm text-white hover:bg-amber-700"
                >
                  Обновить номер в базе
                </button>
                <button
                  type="button"
                  onClick={() => setSerialMismatch(null)}
                  className="rounded border border-amber-300 bg-white px-3 py-1.5 text-sm text-amber-800 hover:bg-amber-100"
                >
                  Оставить как есть
                </button>
              </div>
            </div>
          )}
```
