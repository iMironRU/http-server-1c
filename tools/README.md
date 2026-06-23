# tools/

## test-extension.ps1

Дымовой тест расширения `http_HTTPСервер` на Windows.

### Что делает

1. **install** — применяет `http_HTTPСервер.cfe` к указанной ИБ (`LoadCfg -Extension` + `UpdateDBCfg`)
2. **verify** — выгружает расширение обратно в XML и проверяет наличие 14 ключевых объектов (модули, справочники, регистр, HTTP-сервисы, регламентки)
3. **remove** — удаляет расширение из ИБ
4. **http** — curl-style тесты живых эндпоинтов (требует опубликованную базу)
5. **all** — install + verify + http (если задан `-BaseURL`)

### Требования

- Windows + установленная платформа 1С 8.3.27.x
- PowerShell 5.1+ (входит в Windows 10/11)
- Файл `http_HTTPСервер.cfe` (по умолчанию ищется на Desktop)
- Файловая или серверная ИБ с УТ 11.5.26.96
- Для HTTP-тестов: ИБ опубликована на веб-сервере

### Запуск без подписи

PowerShell по умолчанию блокирует неподписанные скрипты. Один из вариантов:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\test-extension.ps1 -BasePath "C:\Bases\MyUT"
```

Или разово разрешить для текущего сеанса:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\test-extension.ps1 -BasePath "C:\Bases\MyUT"
```

### Примеры

```powershell
# Самый частый: установить и проверить на файловой ИБ
.\test-extension.ps1 -BasePath "C:\Bases\MyUT"

# Только удалить расширение
.\test-extension.ps1 -BasePath "C:\Bases\MyUT" -Action remove

# Полный цикл с HTTP-тестами (требует публикацию)
.\test-extension.ps1 -BasePath "C:\Bases\MyUT" -BaseURL "http://localhost/MyUT" -Action all

# Серверная ИБ
.\test-extension.ps1 -Server "srv01" -InfoBase "MyUT_Dev" -User "Admin" -Password "secret"

# Явный путь к cfe и к платформе
.\test-extension.ps1 `
    -CfeFile "D:\releases\http_HTTPСервер.cfe" `
    -Platform "C:\Program Files\1cv8\8.3.27.2130\bin\1cv8.exe" `
    -BasePath "C:\Bases\MyUT"
```

### Все параметры

| Параметр       | Описание                                                   | Дефолт |
|----------------|------------------------------------------------------------|--------|
| `-Action`      | `install` / `verify` / `remove` / `http` / `all`           | `all`  |
| `-CfeFile`     | Путь к `.cfe`                                              | `$env:USERPROFILE\Desktop\http_HTTPСервер.cfe` |
| `-BasePath`    | Каталог файловой ИБ                                        | —      |
| `-Server`      | Сервер 1С (для серверной ИБ)                               | —      |
| `-InfoBase`    | Имя ИБ на сервере                                          | —      |
| `-User`        | Пользователь ИБ                                            | `Администратор` |
| `-Password`    | Пароль                                                     | (пусто) |
| `-Platform`    | Путь к `1cv8.exe`                                          | автопоиск самой свежей в `C:\Program Files\1cv8\` |
| `-BaseURL`     | URL опубликованной базы для HTTP-тестов                    | —      |
| `-ExtensionName` | Имя расширения для команд designer-а                    | `http_HTTPСервер` |

### Что проверяют HTTP-тесты

| # | Запрос                                                | Ожидание                          |
|---|-------------------------------------------------------|-----------------------------------|
| 1 | `GET /hs/http/ping`                                   | 200, тело содержит "Пинг"         |
| 2 | `GET /hs/swagger/swagger.json`                        | 200, тело содержит "openapi"      |
| 3 | `POST /hs/jrpc/call`<br>`{...,method:"demo.echo",params:{hello:"world"}}` | 200, `"hello":"world"` в ответе |
| 4 | `POST /hs/jrpc/call`<br>`{...,method:"demo.sum",params:[2,3]}` | 200, `"result":5` |
| 5 | `POST /hs/jrpc/call`<br>`{...,method:"unknown.method"}` | 200, `"code":-32601` (Method not found) |

### Коды выхода

- `0` — все проверки прошли
- `1` — есть ошибки (см. вывод)

Удобно вызывать из CI / batch-цикла.
