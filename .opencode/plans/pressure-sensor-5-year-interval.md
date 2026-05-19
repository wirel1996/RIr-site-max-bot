# План: Интервал 5 лет для датчиков давления

## Файл: `services/arshin_service.rb`, строка 292-297

**Заменить:**
```ruby
    suggested_years =
      if year.to_s.strip.empty?
        suggest_search_years(valid_until)
      else
        [year.to_s.strip]
      end
```

**На:**
```ruby
    suggested_years =
      if year.to_s.strip.empty?
        interval = ArshinTypePriority.family_by_serial_key(serial_key) == 'pressure_sensor' ? 5 : VERIFICATION_INTERVAL_YEARS
        suggest_search_years(valid_until, interval_years: interval)
      else
        [year.to_s.strip]
      end
```

## Результат
- Датчик давления с `valid_until` в 2026 → ищет 2026, 2021 (минус 5 лет)
- Остальные приборы → как раньше, минус 4 года
