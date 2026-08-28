# Внутренние адаптеры

[Русский](Adapters.md) · [English](Adapters.en.md)

Адаптеры — единственная разрешённая точка прямого общения с внешним приложением, системным сервисом или CLI. Сейчас они внутренние: протоколы не имеют `public`, а продукт собирается как executable target.

## Общие правила

Каждый адаптер должен:

- иметь стабильную идентичность или однозначно поддерживаемый набор действий;
- объявлять возможности, если разные реализации поддерживают разные функции;
- не импортировать SwiftUI без необходимости;
- не хранить состояние интерфейса;
- возвращать нормализованную модель домена;
- корректно переживать отсутствие приложения, разрешения или данных;
- не выполнять тяжёлую работу на главной очереди;
- не обращаться к другому store напрямую;
- иметь безопасный `start`/`stop`, если он наблюдает за источником.

## Музыка

Контракт: `MusicPlayerAdapter`.

Registry создаёт один общий `MediaController` и три адаптера. `MusicStore` всегда обращается только к адаптеру выбранного `MusicSource`.

### Модели контракта

- `MusicAdapterCapabilities` — доступность like, dislike, seek и upcoming track.
- `MusicCommandContext` — разрешает системный MediaRemote fallback только когда выбранный плеер действительно владеет системной медиасессией.
- `MusicAdapterSnapshot` — нормализованные title, artist, duration, elapsed, playback, artwork и rating.
- `MusicRatingState` — независимые состояния like и dislike.

### Матрица возможностей

| Адаптер | Play/pause | Next/previous | Seek | Like | Dislike | Upcoming |
|---|---:|---:|---:|---:|---:|---:|
| Яндекс Музыка | да | да | да | да | да | да |
| Apple Music | да | да | да | да | нет | да |
| Spotify | да | да | да | да | нет | да |

`да` означает заявленную capability текущего адаптера. Реальная команда всё равно может вернуть типизированную ошибку, например если приложение не установлено, возможность не поддерживается или macOS не дала нужный доступ.

### Стратегия fallback

Яндекс Музыка:

```text
CDP → Accessibility → MediaRemote, если ownsSystemMedia
```

Apple Music и Spotify:

```text
AppleScript → MediaRemote, если ownsSystemMedia
```

Fallback нельзя отправлять чужой активной медиасессии. Для этого каждая команда получает `MusicCommandContext`.

### Добавление внутреннего плеера

1. Добавить новый `MusicSource` с bundle identifier.
2. Реализовать `MusicPlayerAdapter`.
3. Точно объявить capabilities.
4. Добавить адаптер в `MusicAdapterRegistry`.
5. Нормализовать duration и elapsed в секунды.
6. Проверить запуск с закрытым плеером, смену трека, stale elapsed и закрытие процесса.
7. Проверить отсутствие разрешений и отсутствие активной системной медиасессии.

Минимальный каркас внутреннего адаптера:

```swift
final class ExampleMusicAdapter: MusicPlayerAdapter {
    let source = MusicSource.example
    let mediaController: MediaController
    let capabilities = MusicAdapterCapabilities(
        canLike: false,
        canDislike: false,
        canSeek: true,
        canReadUpcomingTrack: false
    )

    init(mediaController: MediaController) {
        self.mediaController = mediaController
    }

    func startPlayback(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func nextTrack(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func previousTrack(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func setDisliked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
}
```

Этот пример относится к текущему внутреннему target и не является API будущего SDK.

## Буфер

Контракт: `ClipboardSourceAdapter`.

```swift
protocol ClipboardSourceAdapter: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var capability: IntegrationCapabilityDeclaration { get }

    func start(receive: @escaping (ClipboardAdapterUpdate) -> Void)
    func stop()
    func copy(_ item: ClipboardItem) -> IntegrationResult
    func remove(_ item: ClipboardItem) -> IntegrationResult
}
```

`ClipboardAdapterUpdate.items` — полный актуальный снимок одного источника. `insertedItem` — необязательная подсказка хосту о новом элементе; она используется для мгновенного preview скриншота.

Встроенные источники:

- `system.text` опрашивает `NSPasteboard` раз в 0,7 секунды и хранит до 60 текстов;
- `system.screenshots` наблюдает за настроенной папкой скриншотов и хранит до 40 файлов.

`ClipboardStore`:

- регистрирует источники;
- объединяет их снимки;
- сортирует элементы по `createdAt`;
- маршрутизирует copy/remove обратно в исходный адаптер;
- хранит pin-состояние независимо от адаптера.

Новый источник можно зарегистрировать до или после начала мониторинга:

```swift
clipboardStore.register(MyClipboardAdapter())
```

Требования к модели:

- `sourceID` совпадает с `adapter.id`;
- `id` остаётся стабильным, если один и тот же элемент публикуется повторно;
- `kind`, `text` и `fileURL` согласованы;
- `start` не создаёт дубликаты watcher;
- `stop` освобождает timer, descriptor и callback.

## Заметки

Контракт: `NotesAppAdapter`.

```swift
protocol NotesAppAdapter {
    var app: NotesApp { get }
    var isInstalled: Bool { get }
    var capability: IntegrationCapabilityDeclaration { get }
    func openNotes() -> IntegrationResult
    func createNote() -> IntegrationResult
}
```

Встроены Apple Notes и Obsidian. `NotesStore` сохраняет выбранное приложение и отправляет обе команды только его адаптеру. `NotesAdapterRegistry` допускает регистрацию и замену адаптера без изменения UI.

## Утилиты

Контракт: `ToolActionAdapter`.

```swift
protocol ToolActionAdapter {
    var supportedActions: Set<ToolAction> { get }
    var capability: IntegrationCapabilityDeclaration { get }
    func perform(_ action: ToolAction) -> IntegrationResult
}
```

`ToolsStore` находит первый адаптер, объявивший нужное действие. Встроенные реализации:

- `SystemToolAdapter` — Calendar и Downloads;
- `DeveloperToolAdapter` — выбор проекта, Git-снимок и быстрые переходы;
- `GitHubToolAdapter` — репозиторий и последнее состояние GitHub Actions через уже авторизованный `gh`.

GitHub-адаптер не хранит токен Hooky bar и не должен его запрашивать: он использует системную авторизацию `gh`.

## Системные события

Bluetooth, VPN, Calendar и AirDrop реализуют общий `SystemEventAdapter`. `SystemFeatureStore` работает с реестром адаптеров и не знает низкоуровневые API конкретного системного события.

Контракт гарантирует:

- стабильный `id`;
- декларация требуемого capability/permission;
- `start(receive:)` и `stop()`;
- нормализованный `HookySystemEvent` без управления интерфейсом;
- deduplication key;
- отсутствие стартового ложного события для уже подключённых устройств и активных VPN.

## Ошибки

Внутренние контракты используют `IntegrationResult` и `IntegrationFailure`. Музыкальный слой использует специализированные `MusicAdapterResult` и `MusicCommandError`, потому что ему дополнительно важно различать владение системной медиасессией.

Типизированные результаты различают как минимум:

- приложение не установлено;
- приложение не запущено;
- доступ запрещён;
- возможность не поддерживается;
- внешний сервис недоступен;
- данные устарели;
- команда принята, но подтверждение ещё не получено.

Адаптер не показывает alert и не меняет UI самостоятельно. Он возвращает результат, а сообщение и реакцию формирует store/host.

## Checklist нового внутреннего адаптера

- [ ] UI не знает конкретный API интеграции.
- [ ] Все команды проходят через store или registry.
- [ ] Capability отражает реальную поддержку.
- [ ] Поздние ответы не применяются после смены источника.
- [ ] Нет тяжёлой работы на main queue.
- [ ] `start`/`stop` идемпотентны.
- [ ] Отсутствие разрешения не приводит к циклу системных запросов.
- [ ] Нет скрытого хранения токенов.
- [ ] Идентификаторы стабильны.
- [ ] Сборка проходит без нового предупреждения.
