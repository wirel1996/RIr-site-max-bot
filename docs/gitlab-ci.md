# GitLab: push и автодеплой на VPS

Сейчас репозиторий на **GitHub** (`origin`). GitLab CI запускается, если проект есть в GitLab и туда уходит код (зеркало или второй remote).

## 1. Проект в GitLab

1. [GitLab](https://gitlab.com) → **New project** → **Create blank project**.
2. Имя, например `max-bot`, visibility по желанию.
3. Запомните URL, например `git@gitlab.com:wirel1996/max-bot.git`.

## 2. Отправить код в GitLab

Из корня репозитория на Windows:

```powershell
git remote add gitlab git@gitlab.com:ВАШ_ЛОГИН/max-bot.git
git push -u gitlab main
```

Дальше можно пушить в оба remote:

```powershell
git push origin main
git push gitlab main
```

Или сделать **GitLab основным** и пушить только туда — CI сработает на каждый push в `main`.

**Зеркало с GitHub** (опционально): GitLab → Settings → Repository → Mirroring repositories → Pull from GitHub.

## 3. SSH-ключ для деплоя (без пароля в CI)

На своём ПК (PowerShell):

```powershell
ssh-keygen -t ed25519 -C "gitlab-ci-deploy-max-bot" -f $env:USERPROFILE\.ssh\gitlab_max_bot_deploy -N '""'
```

Публичный ключ на VPS:

```powershell
type $env:USERPROFILE\.ssh\gitlab_max_bot_deploy.pub | ssh root@95.170.124.182 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Проверка:

```powershell
ssh -i $env:USERPROFILE\.ssh\gitlab_max_bot_deploy root@95.170.124.182 "echo OK"
```

## 4. Переменные в GitLab

**Settings → CI/CD → Variables** (для ветки `main` включите **Protected**):

| Key | Value | Flags |
|-----|--------|--------|
| `DEPLOY_HOST` | `95.170.124.182` | Protected |
| `DEPLOY_USER` | `root` | Protected (опционально, в CI по умолчанию root) |
| `SSH_PRIVATE_KEY` | содержимое файла `gitlab_max_bot_deploy` **без** `.pub` | Protected, Masked, тип **File** |

## 5. Что делает pipeline

- **test** — `bundle exec rspec`, сборка фронта (`npm ci && npm run build`).
- **deploy_production** — только на ветке `main` после успешного test:
  - `git archive` → `scp` на VPS `/root/code-deploy.tgz`;
  - на сервере распаковка в `/opt/max_bot` и `deploy/linux/deploy.sh` (тесты на сервере пропускаются, `SKIP_TESTS=1`).

Первый запуск: **CI/CD → Pipelines** — дождаться зелёного deploy.

## 6. Локальный деплой (как раньше)

`.\deploy-vps.ps1` с `.env.deploy` по-прежнему работает, если нужен деплой без GitLab.

## 7. Типичные ошибки

| Симптом | Решение |
|--------|---------|
| `Permission denied (publickey)` | Проверить `SSH_PRIVATE_KEY` и запись в `authorized_keys` на VPS |
| `Host key verification failed` | В CI уже есть `ssh-keyscan`; проверить `DEPLOY_HOST` |
| test падает на `npm` | Убедиться, что в репозитории закоммичен `web-frontend/package-lock.json` |
| deploy не запускается | Push именно в **default branch** (`main`) |

## 8. Ручной деплой из GitLab

В `.gitlab-ci.yml` можно добавить `when: manual` к job `deploy_production`, если нужно подтверждение перед выкладкой.
