#!/bin/bash
#Дополнительные опции:
#- -s file - использовать альтернативный source-файл
#- -q - тихий режим (только логирование в файл)
#- -b - отключить создание резервных копий
#- -h - показать справку
# Настройки
set -e  # Прерывать выполнение при ошибках
set -u  # Прерывать при использовании неопределенных переменных

# Глобальные переменные
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CONFIG="${SCRIPT_DIR}/source.conf"
LOG_FILE="${SCRIPT_DIR}/replace_configs.log"
VERBOSE=true
BACKUP=true
declare -A variables
found_files=0

# Массив путей к конфигам для обработки
SEARCH_DIRS=(
    "./configs/standalone.xml"
    "./configs/cmj.properties"
    "./configs/server.properties"
    "./configs/standalone.conf"
    "./configs/wildfly.conf"
)

# Функция обработки ошибок
error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR" "Ошибка (код $error_code) в строке $line_no"
    cleanup
    exit $error_code
}
trap 'error_handler ${LINENO} $?' ERR

# Функция очистки
cleanup() {
    log "INFO" "Выполняется очистка временных файлов..."
    rm -f /tmp/replace_configs_*
}
trap cleanup EXIT

# Функция логирования
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] - $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ]; then
        case $level in
            ERROR) echo -e "\e[31m$message\e[0m" ;;    # Красный для ошибок
            WARNING) echo -e "\e[33m$message\e[0m" ;;  # Желтый для предупреждений
            INFO) echo "$message" ;;
        esac
    fi
}

# Проверка зависимостей
check_dependencies() {
    local deps=(sed date mktemp grep cp)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Ошибка: Требуется утилита $dep"
            exit 1
        fi
    done
}

# Проверка существования файла
check_file_exists() {
    local file=$1
    if [ ! -f "$file" ]; then
        log "ERROR" "Файл не найден: $file"
        return 1
    fi
    return 0
}

# Проверка прав доступа
check_permissions() {
    local file=$1
    if [ ! -w "$file" ]; then
        log "ERROR" "Нет прав на запись в файл: $file"
        return 1
    fi
    return 0
}

# Валидация конфига
validate_config() {
    local file=$1
    # Проверка синтаксиса XML
    if [[ $file == *.xml ]]; then
        if command -v xmllint >/dev/null 2>&1; then
            if ! xmllint --noout "$file"; then
                log "ERROR" "Ошибка валидации XML файла: $file"
                return 1
            fi
        fi
    fi
    return 0
}

# Загрузка переменных из source-файла
load_variables() {
    # Объявляем ассоциативный массив
    declare -A variables

    if [ ! -f "$SOURCE_CONFIG" ]; then
        log "ERROR" "Файл source-конфига не найден: $SOURCE_CONFIG"
        exit 1
    fi

    log "INFO" "Загрузка переменных из $SOURCE_CONFIG"
    while IFS='=' read -r key value; do
        # Пропускаем пустые строки и комментарии
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        # Удаляем пробелы
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | tr -d '[:space:]')
        variables["$key"]="$value"
    done < "$SOURCE_CONFIG"

    if [ ${#variables[@]} -eq 0 ]; then
        log "ERROR" "Не удалось загрузить переменные из source-файла"
        exit 1
    fi

    log "INFO" "Загружено ${#variables[@]} переменных"
}

# Замена переменных в файле
replace_variables() {
    local file=$1
    log "INFO" "Обработка файла: $file"

    # Проверка существования файла
    if ! check_file_exists "$file"; then
        return 1
    fi

    # Проверка прав доступа
    if ! check_permissions "$file"; then
        return 1
    fi

    # Создаем бэкап с временной меткой
    if [ "$BACKUP" = true ]; then
        local backup_file="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup_file"
        log "INFO" "Создана резервная копия: $backup_file"
    fi

    # Создаем временный файл
    local temp_file=$(mktemp)
    cp "$file" "$temp_file"

    # Счетчик замен
    local replace_count=0

    # Заменяем переменные
    for key in "${!variables[@]}"; do
        value="${variables[$key]}"
        # Используем более гибкий grep и sed
        if grep -q "\${$key}" "$temp_file"; then
            sed -i "s|\${$key}|$value|g" "$temp_file"
            ((replace_count++))
        fi
    done

    # Проверяем результат
    if [ $replace_count -eq 0 ]; then
        log "WARNING" "Не найдено переменных для замены в $file"
    else
        log "INFO" "Выполнено $replace_count замен в $file"
    fi

    # Проверяем изменения и валидируем
    if ! cmp -s "$temp_file" "$file"; then
        if validate_config "$temp_file"; then
            cp "$temp_file" "$file"
            ((found_files++))
        fi
    fi

    rm "$temp_file"
}

# Показ статистики
show_statistics() {
    log "INFO" "=== Статистика выполнения ==="
    log "INFO" "Обработано файлов: $found_files"
    log "INFO" "Создано резервных копий: $(ls *.bak* 2>/dev/null | wc -l)"
    log "INFO" "Время выполнения: $SECONDS секунд"
}

# Вывод справки
print_usage() {
    echo "Использование: $0 [-s source_config] [-q] [-b] [-h]"
    echo "  -s FILE  использовать альтернативный source-файл"
    echo "  -q       тихий режим"
    echo "  -b       без создания резервных копий"
    echo "  -h       показать эту справку"
}

# Основная логика
main() {
    # Проверка зависимостей
    check_dependencies

    # Обработка параметров командной строки
    while getopts "s:qbh" opt; do
        case $opt in
            s) SOURCE_CONFIG="$OPTARG" ;;
            q) VERBOSE=false ;;
            b) BACKUP=false ;;
            h) print_usage; exit 0 ;;
            \?) print_usage; exit 1 ;;
        esac
    done

    # Инициализация лога
    echo "=== Начало выполнения $(date) ===" > "$LOG_FILE"

    # Загрузка переменных
    load_variables

    # Проверка наличия файлов в массиве
    if [ ${#SEARCH_DIRS[@]} -eq 0 ]; then
        log "ERROR" "Не указаны файлы для обработки в массиве SEARCH_DIRS"
        exit 1
    fi

    # Обработка файлов из массива
    log "INFO" "Начало обработки файлов"
    for file in "${SEARCH_DIRS[@]}"; do
        # Пропускаем закомментированные строки
        [[ $file =~ ^#.*$ ]] && continue
        replace_variables "$file"
    done

    # Вывод статистики
    show_statistics
}

# Запуск скрипта
main "$@"