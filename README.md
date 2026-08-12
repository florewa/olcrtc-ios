# olcRTC for iOS

Обычное iOS-приложение без `NetworkExtension`, которое запускает существующее
Go-ядро olcRTC и публикует локальный SOCKS5 на `127.0.0.1`. Для системного
туннеля используется отдельный клиент из App Store, например Happ.

Проект сохраняет совместимость с сервером и Admin UI из
[`florewa/Olcrtc_manager`](https://github.com/florewa/Olcrtc_manager): панель
создаёт ключи, `client_id`, URI и подписки, а приложение их импортирует.

## Состояние первой версии

Реализовано:

- compact URI панели: `olcrtc://provider@r/...`;
- длинный URI панели: `olcrtc://provider@room/...`;
- `telemost`, `wbstream`, `jitsi`;
- `vp8channel` и `datachannel`;
- загрузка обычных `/sub/<slug>` подписок;
- открытие `olcrtc://subscription?...` deep link;
- расшифровка AES-256-GCM зеркала подписки с Yandex Disk, если VPS недоступен;
- хранение URI, ключей и URL подписок в iOS Keychain;
- локальный SOCKS5 с случайным логином и паролем;
- best-effort привязка WebRTC-сокетов к физическому интерфейсу, чтобы избежать
  петли через Happ при переподключении;
- экспорт SOCKS URI в формате Happ/v2ray;
- background audio keep-alive для sideload-сценария;
- unsigned IPA через GitHub Actions.

Пока не реализовано:

- SOCKS5 UDP ASSOCIATE в ядре olcRTC;
- встроенный iOS `NetworkExtension` (он намеренно не нужен);
- публикация в App Store.

## Архитектура

```text
приложения iPhone
  -> Happ Packet Tunnel
    -> SOCKS5 127.0.0.1:10808
      -> olcRTC iOS
        -> WebRTC / Telemost, WB Stream или Jitsi
          -> olcRTC server
            -> интернет
```

olcRTC необходимо запустить **до включения Happ**. Это позволяет сначала
установить WebRTC-соединение с разрешённой платформой. Если WebRTC пришлось
переподключать и это не получилось при активном Happ, выключите Happ,
перезапустите туннель в olcRTC и снова включите Happ.

## Чистая установка сервера

Сейчас сервер, ключи и подписки заранее не нужны. Когда будет VPS с Linux и
`systemd`, официальный установщик панели запускается так:

```bash
curl -fsSL https://raw.githubusercontent.com/florewa/Olcrtc_manager/master/server-install/olcrtc-setup.sh | sudo bash
```

После установки:

1. Открыть адрес Admin UI, который напечатает установщик.
2. Сохранить напечатанный установщиком случайный пароль панели.
3. Создать экземпляр `telemost + vp8channel` или `wbstream + vp8channel`.
4. Панель сама создаст ключ и `client_id`.
5. Скопировать `olcrtc://` URI либо создать подписку и скопировать её URL.
6. Импортировать URI/подписку в iOS-приложение.

Не публикуйте URI, QR-код и subscription URL: они содержат секреты доступа.
Для URL подписки нужен HTTPS с сертификатом, которому доверяет iOS. Клиент
намеренно не отключает проверку TLS для самоподписанного сертификата панели.

## Получение IPA без Mac

1. Создать новый GitHub-репозиторий и загрузить туда содержимое этого каталога.
2. Открыть `Actions -> Build unsigned iOS IPA -> Run workflow`.
3. Оставить `core_ref=server-v1.9.70`. При обновлении сервера собирать клиент
   из того же тега.
4. Дождаться зелёной сборки.
5. Скачать artifact `olcrtc-ios-unsigned`.
6. Проверить SHA-256 из соседнего файла.
7. Установить IPA на iPhone через Sideloadly на Windows с бесплатным Apple ID.

Бесплатная подпись действует семь дней. В Sideloadly следует включить automatic
refresh; дома приложение будет переподписываться при обнаружении iPhone через
Wi-Fi или USB.

## Использование на iPhone

1. Установить Happ из App Store.
2. Открыть olcRTC и добавить URI или URL подписки.
3. Выбрать конфигурацию и нажать «Запустить туннель».
4. Дождаться `SOCKS готов`.
5. Нажать «Скопировать конфигурацию для Happ».
6. В Happ выбрать `+ -> Import from clipboard`.
7. Включить добавленный профиль Happ.

Порт и учётные данные SOCKS сохраняются в Keychain, поэтому профиль Happ обычно
остаётся действующим после перезапуска. Импортируйте его заново, если меняли порт
в настройках приложения.

## Локальная сборка на macOS

Требуются Xcode, Go 1.25+, XcodeGen, `gomobile` и `gobind`:

```bash
brew install xcodegen
go install golang.org/x/mobile/cmd/gomobile@v0.0.0-20260410095206-2cfb76559b7b
go install golang.org/x/mobile/cmd/gobind@v0.0.0-20260410095206-2cfb76559b7b
sh Scripts/test-ios.sh
sh Scripts/build-ipa.sh ../Olcrtc_manager
```

Результат: `build/olcrtc-ios-unsigned.ipa`.

## Безопасность и ограничения

- Keychain использует `AfterFirstUnlockThisDeviceOnly`; секреты не мигрируют на
  другое устройство через резервную копию.
- Полные URI не должны попадать в логи и скриншоты.
- Background audio keep-alive не гарантирует вечную работу: звонок, смена
  аудиосессии или нехватка памяти могут остановить приложение.
- Текущий SOCKS olcRTC поддерживает TCP CONNECT. UDP, некоторые игры, звонки и
  обязательный QUIC пока не пройдут.
- Доступность Telemost/WB/Jitsi зависит от оператора, региона и текущих правил
  фильтрации; ни один провайдер нельзя считать гарантированным навсегда.

## Лицензии

Код iOS-клиента распространяется под MIT. Подход с фоновым аудио и формат
импорта в Happ адаптированы из MIT-проекта `kulikov0/whitelist-bypass`; сведения
сохранены в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
