#!/bin/bash
#./replace_configs.sh                     # Стандартный запуск
#./replace_configs.sh -s other.conf       # Использовать другой source-файл
#./replace_configs.sh -q                  # Тихий режим
#./replace_configs.sh -b                  # Без создания бэкапов
#./replace_configs.sh -d                  # Режим dry-run
#./replace_configs.sh -h                  # Показать справку

# Константы
readonly SCRIPT_NAME=$(basename "$0")
readonly VERSION="1.0.1"
readonly DEFAULT_SOURCE_CONFIG="source.conf"
readonly LOG_FILE="replace_configs.log"

# Конфигурационные файлы для обработки
readonly SEARCH_DIRS=(
    "./configs/standalone.xml"
    "./configs/cmj.properties"
    "./configs/server.properties"
    "./configs/standalone.conf"
    "./configs/wildfly.conf"
)

# Глобальные переменные
declare -A variables
BACKUP=true
VERBOSE=true
DRY_RUN=false
SOURCE_CONFIG="$DEFAULT_SOURCE_CONFIG"
TEMP_FILE=""

# Функция вывода справки
show_help() {
    cat << EOF
Использование: $SCRIPT_NAME [ОПЦИИ]
Заменяет переменные в конфигурационных файлах.

Опции:
    -s FILE    Использовать альтернативный source-файл (по умолчанию: $DEFAULT_SOURCE_CONFIG)
    -q         Тихий режим
    -b         Без создания резервных копий
    -d         Dry-run (показать, что будет сделано, без реальных изменений)
    -h         Показать эту справку
    -v         Показать версию

Примеры:
    $SCRIPT_NAME                     # Стандартный запуск
    $SCRIPT_NAME -s other.conf       # Использовать другой source-файл
    $SCRIPT_NAME -q                  # Тихий режим
    $SCRIPT_NAME -b                  # Без создания бэкапов
EOF
    exit 0
}

# Функция логирования
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ] || [ "$level" = "ERROR" ]; then
        echo "[$level] $message"
    fi
}

# Проверка прав доступа
check_permissions() {
    local file=$1
    if [ ! -w "$file" ]; then
        log "ERROR" "Нет разрешения на запись в файл: $file"
        return 1
    fi
    return 0
}

# Загрузка переменных из source файла
load_variables() {
    if [ ! -f "$SOURCE_CONFIG" ]; then
        log "ERROR" "Исходный конфигурационный файл не найден: $SOURCE_CONFIG"
        exit 1
    fi

    while IFS='=' read -r key value; do
        # Пропускаем пустые строки и комментарии
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Очистка от пробелов
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | tr -d '[:space:]')

        if [ -n "$key" ] && [ -n "$value" ]; then
            variables[$key]=$value
        fi
    done < "$SOURCE_CONFIG"

    # Обработка HOSTNAME
    if [ "${variables[HOSTNAME]}" = "default" ] || [ -z "${variables[HOSTNAME]}" ]; then
        variables["HOSTNAME"]=$(hostname)
    fi
}

# Функция замены переменных
replace_variables() {
    local file=$1
    log "INFO" "Обработка файла: $file"

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY-RUN] Симуляция обработки файла: $file"
        return 0
    fi

    if ! check_permissions "$file"; then
        return 1
    fi

    if [ "$BACKUP" = true ]; then
        cp "$file" "${file}.bak"
    fi

    cp "$file" "$TEMP_FILE"

    for key in "${!variables[@]}"; do
        value="${variables[$key]}"
        search_pattern="\${$key}"
        escaped_value=$(printf '%s\n' "$value" | sed 's:[][\/@\#$.*/&]:\\&:g')
        sed -i "s|$search_pattern|$value|g" "$TEMP_FILE"
    done

    if cmp -s "$TEMP_FILE" "$file"; then
        log "INFO" "Никаких изменений для $file"
        [ "$BACKUP" = true ] && rm "${file}.bak"
    else
        cp "$TEMP_FILE" "$file"
        log "INFO" "Обновлен файл $file"
    fi
}

# Функция очистки
cleanup() {
    [ -n "$TEMP_FILE" ] && [ -f "$TEMP_FILE" ] && rm "$TEMP_FILE"
    exit 0
}

# Основная логика
main() {
    # Создание временного файла
    TEMP_FILE=$(mktemp)
    trap cleanup SIGINT SIGTERM EXIT

    # Загрузка переменных
    load_variables
    # Проверка файлов
    local found_files=0
    for file in "${SEARCH_DIRS[@]}"; do
        if [ -f "$file" ]; then
            replace_variables "$file"
            ((found_files++))
        else
            log "WARNING" "Файл не найден: $file"
        fi
    done

    if [ $found_files -eq 0 ]; then
        log "WARNING" "Не найдено ни одного конфигурационного файла"
    else
        log "INFO" "Обработка завершена. Обработано файлов: $found_files"
    fi
}

# Обработка параметров командной строки
while getopts "s:qbdhv" opt; do
    case $opt in
        s) SOURCE_CONFIG="$OPTARG" ;;
        q) VERBOSE=false ;;
        b) BACKUP=false ;;
        d) DRY_RUN=true ;;
        h) show_help ;;
        v) echo "$SCRIPT_NAME версия $VERSION"; exit 0 ;;
        *) echo "Используйте -h для получения справки"; exit 1 ;;
    esac
done

# Запуск основной логики
main
