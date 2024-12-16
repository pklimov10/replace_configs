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