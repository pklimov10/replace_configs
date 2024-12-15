▎Общее описание
Скрипт предназначен для автоматической замены переменных в конфигурационных файлах. Он читает значения переменных из source файла и подставляет их в целевые конфигурационные файлы.

▎Запуск
./replace_configs.sh                    # Стандартный запуск
./replace_configs.sh -s other.conf      # Использовать другой source-файл
./replace_configs.sh -q                 # Тихий режим
./replace_configs.sh -b                 # Без создания бэкапов

▎Структура файлов
1. source файл (например, variables.conf):

   HOSTNAME=default
   PORT=8080
   DB_NAME=mydb


2. Целевой конфигурационный файл (например, config.xml):

   <server>
     <host>${HOSTNAME}</host>
     <port>${PORT}</port>
     <database>${DB_NAME}</database>
   </server>


▎Особенности работы с HOSTNAME
- Если в source файле указано HOSTNAME=default или HOSTNAME не задан:
  - Скрипт автоматически использует системное имя хоста
- Если в source файле указано конкретное значение HOSTNAME:
  - Будет использовано заданное значение

▎Возможные проблемы и их решение

1. Скрипт не заменяет переменные:
   - Проверить права доступа к файлам
   - Убедиться, что имена переменных в source и целевом файле совпадают
   - Проверить формат переменных (должны быть в виде ${VARIABLE})

2. Неправильное значение HOSTNAME:
   - Проверить значение в source файле
   - Проверить системное имя хоста командой hostname

3. Ошибки синтаксиса:
   - Проверить отсутствие лишних пробелов в source файле
   - Убедиться, что каждая переменная записана в формате KEY=VALUE

▎Команды для диагностики

# Проверка системного имени хоста
hostname

# Просмотр содержимого source файла
cat variables.conf

# Просмотр прав доступа
ls -l variables.conf
ls -l config.xml

# Проверка лога скрипта (если настроено логирование)
tail -f script.log

▎Лицензия
KP © 2024 KlimovPavel. All rights reserved.