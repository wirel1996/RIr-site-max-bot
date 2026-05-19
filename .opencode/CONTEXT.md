# Контекст проекта: RIr-site-max-bot

## О проекте
Бот для платформы MAX (ранее Telegram) + веб-приложение для управления контактами, приборами учёта, расписаниями и биллингом.

## Структура
- `bot.rb` — основной бот MAX (2875 строк)
- `services/` — сервисы (26 файлов): arshin, yadisk, sheets, billing, contacts, water_registry, uute и др.
- `storage/` — SQLite хранилища: user_profiles, contacts_db, uute_db, water_registry_db, journal_db и др.
- `web/app.rb` — Sinatra API для web-frontend
- `web-frontend/` — React + TypeScript фронтенд

## Ключевые модули
1. **АРШИН** — поиск приборов поверки, PDF-документы
2. **Яндекс.Диск** — загрузка фото/документов
3. **Google Sheets** — расписания заданий, уведомления
4. **Контакты** — категории (ГСПО, ФЛ, ЮЛ, бюджет и др.), синхронизация
5. **Приборы учёта (УУТЭ/ГСПО)** — карточки, поверки, акты, пломбы, показания
6. **Летняя вода ГСПО** — реестр заявок, телефонограммы, выгрузка отключённых точек
7. **Электронные журналы** — задания по дням, уведомления
8. **ГВС биллинг** — показания, поиск, создание месяцев
9. **Алгоритмы** — пошаговые инструкции
10. **Расчёты** — тепловая нагрузка, дроссельная диафрагма

## Последние задачи (обратный хронологический порядок)

### 2026-05-19 — Выгрузка приборов учёта ГСПО
- Добавлен `GET /api/metering/gspo/export` — Excel со всеми объектами ГСПО
- 72 столбца в порядке карточки (от "Номер по списку" до "Примечание")
- Кнопка "Выгрузить объекты" на странице ГСПО рядом с "Загрузить Excel"
- Форматирование: "Наименование" и "Адрес" — перенос строк, ширина 40; даты — ширина 12
- Исправлена проблема с ключами: `record[key.to_sym]` (public_row возвращает символы)
- Файлы: `uute_service.rb` (EXPORT_COLUMNS, export_all), `uute_db.rb` (all_gspo), `app.rb`, `metering.ts`, `MeteringGspo.tsx`

### 2026-05-19 — Выгрузка отключённых точек (летняя вода)
- `GET /api/metering/water/disconnected-export` — Excel с уникальными точками где water_supplied != 'да'
- Только столбец "Точка", разбито по 20 на столбец
- Каскадное обновление: при установке water_supplied='да' на одной записи — все с той же actual_connection_point тоже получают 'да'
- Файлы: `water_registry_db.rb`, `water_registry_service.rb`, `app.rb`, `metering.ts`, `WaterRegistry.tsx`

### 2026-05-19 — Перенос репозитория
- Remote изменён на `git@github.com:wirel1996/RIr-site-max-bot.git`
- Секреты Google OAuth исключены из `.gitignore` (.claude/settings.local.json)

## Важные детали
- **Timezone**: Asia/Novosibirsk (бот), Asia/Tomsk (шедулеры)
- **MAX API**: https://platform-api.max.ru/messages
- **WaterRegistry**: каскадное обновление water_supplied только по actual_connection_point (без fallback на point_number)
- **Sinatra маршруты**: специфичные роуты должны идти ПЕРЕД параметрическими (disconnected-export перед water/:id)
- **public_row** в UuteService возвращает хеш с символьными ключами

## Команды
- Запуск бота: `ruby bot.rb`
- Запуск веб: `ruby web/app.rb`
- Деплой: `deploy.ps1`
