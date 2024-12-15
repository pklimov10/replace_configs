#!/bin/bash
#./replace_configs.sh                    # Стандартный запуск
#./replace_configs.sh -s other.conf      # Использовать другой source-файл
#./replace_configs.sh -q                 # Тихий режим
#./replace_configs.sh -b                 # Без создания бэкапов

# Путь к конфигу с данными для замены
SOURCE_CONFIG="source.conf"

# Массив путей к конфигам для обработки
SEARCH_DIRS=(
    "./standalone.xml"
    #"/path/to/dir2/config2.conf"
    #"/path/to/dir3/config3.conf"
    # Добавьте нужные файлы
)

# Проверка существования source файла
if [ ! -f "$SOURCE_CONFIG" ]; then
    echo "Ошибка: Исходный конфигурационный файл не найден: $SOURCE_CONFIG"
    exit 1
fi

# Проверка доступности файлов
for file in "${SEARCH_DIRS[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Предупреждение: файл не найден или недоступен: $file"
    fi
done

# Создаем временный файл
TEMP_FILE=$(mktemp)

# Загружаем все переменные из source конфига в ассоциативный массив
declare -A variables
while IFS='=' read -r key value; do
    # Пропускаем пустые строки и комментарии
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

    # Убираем пробелы
    key=$(echo "$key" | tr -d '[:space:]')
    value=$(echo "$value" | tr -d '[:space:]')

    if [ -n "$key" ] && [ -n "$value" ]; then
        variables[$key]=$value
    fi
done < "$SOURCE_CONFIG"
# Читаем значение HOSTNAME из source файла
source_hostname="${variables[HOSTNAME]}"

# Проверяем, если HOSTNAME равен "default" или пустой,
# то берем значение из системы, иначе оставляем из source файла
if [ "$source_hostname" = "default" ] || [ -z "$source_hostname" ]; then
    variables["HOSTNAME"]=$(hostname)
fi
# Функция для замены переменных в файле
replace_variables() {
    local file=$1
    echo "Processing file: $file"

    # Проверка прав доступа
    if ! check_permissions "$file"; then
        return 1
    fi

    # Создаем бэкап файла
    if [ "$BACKUP" = true ]; then
        cp "$file" "${file}.bak"
    fi

    # Копируем исходный файл во временный
    cp "$file" "$TEMP_FILE"

    # Заменяем каждую переменную
for key in "${!variables[@]}"; do
    value="${variables[$key]}"
    search_pattern="\${$key}"
 # Экранируем специальные символы в значении переменной
    escaped_value=$(printf '%s\n' "$value" | sed 's:[][\/@\#$.*/&]:\\&:g')
    # Оставляем значение как есть, с кавычками или без
    sed -i "s|$search_pattern|$value|g" "$TEMP_FILE"
done

    # Проверяем, были ли изменения
    if cmp -s "$TEMP_FILE" "$file"; then
        log "Никаких изменений для $file"
        [ "$BACKUP" = true ] && rm "${file}.bak"
    else
        cp "$TEMP_FILE" "$file"
        log "Обновленный $file (резервная копия сохранена как ${file}.bak)"
    fi
}

# Параметры по умолчанию
BACKUP=true
VERBOSE=true

# Обработка параметров командной строки
while getopts "s:qb" opt; do
    case $opt in
        s) SOURCE_CONFIG="$OPTARG" ;;
        q) VERBOSE=false ;;
        b) BACKUP=false ;;
        \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
    esac
done

# Логирование
LOG_FILE="replace_configs.log"
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ]; then
        echo "$message"
    fi
}

# Проверка прав доступа
check_permissions() {
    local file=$1
    if [ ! -w "$file" ]; then
        log "Ошибка: Нет разрешения на запись в файл: $file"
        return 1
    fi
    return 0
}

# Очистка при завершении
cleanup() {
    [ -f "$TEMP_FILE" ] && rm "$TEMP_FILE"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Обрабатываем все файлы
found_files=0
for config_file in "${SEARCH_DIRS[@]}"; do
    if [ -f "$config_file" ]; then
        replace_variables "$config_file"
        ((found_files++))
    fi
done

if [ $found_files -eq 0 ]; then
    log "По указанным путям не найдено ни одного конфигурационного файла"
else
    log "Обновление конфигурации завершено! Обработанный $found_files файл."
fi

# Удаляем временный файл
rm "$TEMP_FILE"
