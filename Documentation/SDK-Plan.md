# План HookyBar SDK

[Русский](SDK-Plan.md) · [English](SDK-Plan.en.md)

Публичного SDK пока нет. Этот документ фиксирует направление и границы первой версии, но не обещает стабильность приведённых имён типов.

## Зачем нужен SDK

SDK должен позволить добавить интеграцию, не импортируя внутренние сторы и не изменяя основной executable target. При этом Hooky bar сохраняет контроль над:

- геометрией острова;
- анимациями открытия и закрытия;
- очередью событий;
- разрешениями;
- жизненным циклом;
- производительностью;
- единым визуальным стилем.

## Не цели первой версии

В первой версии расширение не должно:

- получать произвольный доступ к `MusicStore`, `ClipboardStore` или `InterfaceModel`;
- менять размер `NSPanel`;
- рисовать полностью произвольное SwiftUI-окно внутри острова;
- читать чужие данные без capability;
- загружать неподписанный исполняемый код без проверки;
- обходить host и напрямую управлять другими расширениями.

## Предлагаемые модули

```text
HookyBarCore       value-модели, IDs, capabilities, errors
HookyBarSDK        публичные protocols и host context
HookyBarHost       registry, lifecycle, permissions, event queue
HookyBar           приложение и встроенные adapters
```

Встроенные адаптеры должны использовать тот же публичный контракт, что и сторонние. Иначе SDK быстро разойдётся с реальным поведением приложения.

## Расширения первой версии

Приоритетный минимальный набор:

1. **Tool action** — команда и стандартная карточка/кнопка.
2. **Compact event** — короткое системное уведомление, использующее существующую геометрию mini-player.
3. **Clipboard source** — поставщик текстов, файлов или изображений.
4. **Settings section** — типизированные настройки из стандартных контролов.

Музыкальные player adapters лучше открыть после стабилизации typed errors и state acknowledgement: этот контракт сложнее обычной команды.

## Manifest

Предлагаемый manifest должен быть декларативным:

```json
{
  "identifier": "dev.example.hooky.github",
  "name": "GitHub Status",
  "version": "0.1.0",
  "minimumHostVersion": "0.2.0",
  "entryPoint": "GitHubExtension",
  "capabilities": ["network", "openURL"],
  "contributions": ["tool", "compactEvent"]
}
```

Точные ключи будут утверждены после выбора модели доставки расширений.

## Жизненный цикл

```text
discover
  → validate manifest and compatibility
  → ask/verify capabilities
  → instantiate
  → start(context)
  → receive actions / publish snapshots
  → stop()
  → release
```

Повторный `start` не допускается без `stop`. Host должен иметь возможность отключить зависшее расширение и показать диагностическую ошибку в Dev-разделе.

## Предлагаемые базовые типы

Иллюстрация направления, не текущий API:

```swift
public struct HookyExtensionID: Hashable, Codable, Sendable {
    public let rawValue: String
}

public enum HookyCapability: String, Codable, Sendable {
    case clipboardRead
    case clipboardWrite
    case fileRead
    case network
    case automation
    case accessibility
    case openURL
}

public enum HookyAdapterError: Error, Sendable {
    case permissionDenied(HookyCapability)
    case unavailable
    case unsupported
    case invalidData
    case timedOut
    case externalFailure(String)
}
```

Все value-типы публичного API должны быть `Sendable`, где это возможно. AppKit и SwiftUI-типы не должны попадать в transport-модели; например, artwork лучше передавать как data/file reference, а цвет — как codable token.

## UI contributions

Первая версия должна предоставлять компоненты, а не произвольный canvas:

- title и subtitle;
- SF Symbol или проверенный asset;
- semantic tint;
- одна основная и одна дополнительная команда;
- progress или status;
- стандартные compact/expanded presentation hints.

Host context также должен передавать расширению текущую `Locale` и уведомлять о её изменении. Пользовательские строки расширения должны локализоваться самим расширением, а host локализует стандартные кнопки, статусы и ошибки.

Host сам применяет `HookyTheme`, `HookyMotion` и `HookySurfaceLayout`. Так стороннее расширение не ломает общую анимацию и hit testing.

## Безопасность

До выбора формата доставки нельзя считать SDK готовым. Нужно решить:

- in-process Swift bundle или отдельный XPC process;
- подпись и проверка Team ID;
- каталог установки;
- обновление и rollback;
- per-extension settings storage;
- ограничение CPU, памяти и частоты событий;
- логирование без утечки содержимого буфера и токенов.

Для сторонних расширений предпочтителен отдельный процесс/XPC: это сложнее, но падение или зависание интеграции не уничтожит панель.

## Этапы реализации

### Этап 0 — beta-gate: стабилизация внутренних контрактов

- [x] описать существующие адаптеры;
- [x] зафиксировать правила зависимостей;
- [x] составить матрицу разрешений;
- [x] заменить `Bool` на typed result;
- [x] сделать Music registry внутренне расширяемым;
- [x] сделать Notes registry внутренне расширяемым;
- [x] унифицировать system event adapters;
- [x] добавить машинно-читаемые capability-декларации;
- [x] добавить test doubles и регрессионные тесты контрактов.

После выполнения этапа 0 и release-проверки выходит публичная бета Hooky bar. Следующие этапы начинаются после сбора и исправления её реальных ошибок.

### Этап 1 — после беты: пакеты Core и SDK

- [ ] выделить value-модели в library target;
- [ ] определить semantic versioning;
- [ ] сделать registry и lifecycle;
- [ ] перевести встроенный Tool adapter на новый контракт;
- [ ] написать unit tests совместимости.

### Этап 2 — первая внешняя интеграция

- [ ] создать `HelloHooky` example;
- [ ] добавить Tool contribution;
- [ ] добавить Compact event contribution;
- [ ] показать ошибки и состояние расширения в Dev-разделе;
- [ ] измерить CPU/RAM и поведение при аварии.

### Этап 3 — Clipboard и настройки

- [ ] открыть Clipboard source API;
- [ ] добавить standard settings schema;
- [ ] capability prompts;
- [ ] миграция настроек между версиями.

### Этап 4 — дистрибуция

- [ ] подпись;
- [ ] установка и удаление;
- [ ] обновление и rollback;
- [ ] документация для авторов;
- [ ] шаблон проекта расширения.

## Критерий готовности SDK 0.1

SDK 0.1 готов, когда внешнее example-расширение можно установить без изменения репозитория Hooky bar, оно добавляет один Tool и одно compact-событие, запрашивает только объявленные capabilities, отключается без перезапуска приложения и не имеет доступа к внутренним сторам.
