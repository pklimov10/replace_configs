▎Управление конфигурациями серверов
Скрипт для управления конфигурациями с поддержкой групп серверов.

▎Использование
./script_name [ОПЦИИ]

▎Основные опции

| Опция | Описание |
|-------|----------|
| -g GROUP | Указать группу серверов |
| -s FILE | Использовать альтернативный source-файл |
| -q | Тихий режим |
| -b | Без создания резервных копий |
| -d | Dry-run (показать изменения без применения) |
| -h | Показать справку |
| -v | Показать версию |

▎Управление группами

| Команда | Описание |
|---------|----------|
| --list-groups | Показать список групп |
| --add-group NAME PATH | Добавить новую группу |
| --remove-group NAME | Удалить группу |
| --rename-group OLD NEW | Переименовать группу |
| --clone-group SRC DST | Клонировать группу |

▎Управление бэкапами

| Команда | Описание |
|---------|----------|
| --create-backup GROUP | Создать резервную копию |
| --restore-backup GROUP TS | Восстановить из резервной копии |
| --list-backups GROUP | Показать список резервных копий |
| --cleanup-backups GROUP | Очистить старые резервные копии |

▎Управление переменными

| Команда | Описание |
|---------|----------|
| --validate [GROUP] | Проверить переменные |
| --show-vars [GROUP] | Показать переменные |
| --diff-vars GROUP1 GROUP2 | Сравнить переменные групп |
| --search-var PATTERN | Найти переменную |

▎Примеры использования
# Запуск для группы prod
./script_name -g prod

# Показать список групп
./script_name --list-groups

# Создать бэкап prod
./script_name --create-backup prod

# Показать переменные dev
./script_name --show-vars dev


▎Требования
- Bash 4.0 или выше
- Стандартные Unix-утилиты

▎Установка
1. Скачайте скрипт
2. Сделайте его исполняемым:
   chmod +x script_name

▎Конфигурация системы

▎Содержание
- [Основные настройки](#основные-настройки)
- [Настройки безопасности](#настройки-безопасности)
- [Базы данных](#базы-данных)
- [Сервисы и интеграции](#сервисы-и-интеграции)
- [Настройки производительности](#настройки-производительности)

▎Основные настройки

▎Настройки хоста
HOSTNAME=default  # Системное имя хоста


▎Серверы ActiveMQ Artemis

`artemis01=192.168.1.1
artemis02=192.168.1.2
`

▎Настройки безопасности

▎Java KeyStore

`JKS=/path/to/keystore.jks
JKSPASS=your_keystore_password`


▎KeyCloak

`KEYCLOAK_URL=https://keycloak.example.com
KEYCLOAK_REALM_NAME=realm
KEYCLOAK_CLIENT_ID=client
KEYCLOAK_TRUSTSTORE=/path/to/truststore`


▎Базы данных

▎CM5 Database

`DB_HOST_CM5=localhost
DB_PORT_CM5=5432
DB_NAME_CM5=cm5_db
DB_USER_CM5=user
DB_PASS_CM5=password`


▎CMR Database

`DB_HOST_CMR=localhost
DB_PORT_CMR=5432
DB_NAME_CMR=cmr_db
DB_USER_CMR=user
DB_PASS_CMR=password`


▎CMJ Database

`DB_HOST_CMJ=localhost
DB_PORT_CMJ=5432
DB_NAME_CMJ=cmj_db
DB_USER_CMJ=user
DB_PASS_CMJ=password`


▎Driver

`driver=org.postgresql.Driver-42.2.5
`

▎Сервисы и интеграции

▎URL endpoints

`solr_url=http://solr.example.com
entrypoint_url=http://api.example.com
sedsvcMedo_entrypoint_url=http://medo.example.com
`

▎Почтовый сервер

`mail_server_host=smtp.example.com
MAIL_SERVER_PORT=587
MAIL_DEFAULT_SENDER=noreply@example.com
MAIL_USERNAME=user@example.com`


▎Журнал безопасности

`sej_api_entry_point=http://sej.example.com/api
`

▎Хранилища

`ATTACHMENT_STORAGE=/path/to/attachments
ATTACHMENT_TEMP_STORAGE=/path/to/temp`


▎Настройки производительности

▎Кэширование

`GLOBAL_CACHE_ENABLED=true
GLOBAL_CACHE_MODE=distributed
GLOBAL_CACHE_MAX_SIZE=1000
GLOBAL_CACHE_CLUSTER_MODE=sync`


▎JVM параметры

`JAVA_XMS=2G
JAVA_XMX=4G
JAVA_MAX_METASPACE=512M
JAVA_GC_LOG_PATH=/path/to/gc.log
JAVA_TMP_DIR=/path/to/tmp`


▎Настройки выполнения задач

`
CM_TASKS_EXECUTOR_QUEUE_CAPACITY=100
CM_TASKS_EXECUTOR_POOL_SIZE=10
`

▎Дополнительные параметры

`FORCE_DB_CONSISTENCY_CHECK=true
AM_AUTOSTART_ENABLED=true`


▎Примечания

- Все пути должны быть абсолютными
- Пароли должны быть надежно защищены
- Рекомендуется регулярное резервное копирование баз данных
- Параметры JVM следует настраивать в соответствии с доступными ресурсами сервера