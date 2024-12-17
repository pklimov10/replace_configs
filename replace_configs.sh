#!/bin/bash

###########################################
# ПОЛЬЗОВАТЕЛЬСКИЕ НАСТРОЙКИ
###########################################

# Базовые пути
WF_HOME="/opt/wildfly"                        # Директория WildFly
BASE_CONFIG_DIR="./configs"           # Базовая директория для конфигураций
BASE_BACKUP_DIR="./backups"           # Базовая директория для резервных копий
BASE_LOG_DIR="./log"                  # Базовая директория для логов
GOLD_CONFIG_DIR="./GOLD_CONFIG"              # Директория с эталонными конфигурациями
# Настройки групп
GROUPS_CONFIG="${BASE_CONFIG_DIR}/groups.conf"  # файл для хранения групп

# Настройки групп
#AVAILABLE_GROUPS=("app" "kma" "rep" "tech" "dev")
# Пути к конфигурационным файлам для каждой группы
load_groups() {
    AVAILABLE_GROUPS=()
    SOURCE_CONFIG_PATHS=()

    if [[ ! -f "$GROUPS_CONFIG" ]]; then
        # Инициализация файла групп по умолчанию
        touch "$GROUPS_CONFIG"
        echo "app:${BASE_CONFIG_DIR}/app/variables.conf" >> "$GROUPS_CONFIG"
        echo "kma:${BASE_CONFIG_DIR}/kma/variables.conf" >> "$GROUPS_CONFIG"
        echo "rep:${BASE_CONFIG_DIR}/rep/variables.conf" >> "$GROUPS_CONFIG"
        echo "tech:${BASE_CONFIG_DIR}/tech/variables.conf" >> "$GROUPS_CONFIG"
        echo "dev:${BASE_CONFIG_DIR}/dev/variables.conf" >> "$GROUPS_CONFIG"
    fi

    # Чтение групп из файла
    while IFS=':' read -r group config_path; do
        AVAILABLE_GROUPS+=("$group")
        SOURCE_CONFIG_PATHS["$group"]="$config_path"
    done < "$GROUPS_CONFIG"
}

# Вызываем загрузку групп при инициализации
save_groups() {
    # Очистка текущего файла групп
    > "$GROUPS_CONFIG"

    # Сохранение текущих групп
    for group in "${AVAILABLE_GROUPS[@]}"; do
        echo "$group:${SOURCE_CONFIG_PATHS[$group]}" >> "$GROUPS_CONFIG"
    done
}

# Вызываем загрузку групп при инициализации
load_groups

# Конфигурационные файлы для обработки
SEARCH_DIRS=(
    "${WF_HOME}/standalone.xml"
    "${WF_HOME}/cmj.properties"
    "${WF_HOME}/server.properties"
    "${WF_HOME}/standalone.conf"
    "${WF_HOME}/wildfly.conf"
)

# Настройки бэкапов
BACKUP_RETENTION_DAYS=30                       # Срок хранения резервных копий (в днях)
DEFAULT_BACKUP_PREFIX="backup"                 # Префикс для имен резервных копий

# Настройки логирования
LOG_FILE="${BASE_LOG_DIR}/replace_configs.log" # Путь к файлу логов
LOG_MAX_SIZE=10M                              # Максимальный размер лог-файла
LOG_ROTATE_COUNT=5                            # Количество ротаций лог-файла

# Настройки безопасности
REQUIRED_PERMISSIONS="0644"                    # Права доступа для новых файлов
SECURE_DIRECTORIES="0755"                      # Права доступа для новых директорий

# Дополнительные настройки
TEMP_DIR="/tmp/config_manager"                # Директория для временных файлов
LOCK_FILE="/tmp/config_manager.lock"          # Файл блокировки для предотвращения параллельного запуска
SCRIPT_TIMEOUT=3600                           # Таймаут выполнения скрипта (в секундах)

###########################################
# СИСТЕМНЫЕ КОНСТАНТЫ (не изменять)
###########################################

readonly SCRIPT_NAME=$(basename "$0")
readonly VERSION="1.2.1"
readonly DEFAULT_SOURCE_CONFIG_PATH="${BASE_CONFIG_DIR}/variables.conf"

###########################################
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
###########################################

declare -A variables
BACKUP=true
VERBOSE=true
DRY_RUN=false
SERVER_GROUP=""
CUSTOM_SOURCE=""
SOURCE_CONFIG=""
TEMP_FILE=""
# Пути копирования файлов из GOLD
declare -A GOLD_TARGET_PATHS=(
    ["standalone.xml"]="${WF_HOME}/standalone.xml"
    ["cmj.properties"]="${WF_HOME}/cmj.properties"
    ["server.properties"]="${WF_HOME}/server.properties"
    ["standalone.conf"]="${WF_HOME}/standalone.conf"
    ["wildfly.conf"]="${WF_HOME}/wildfly.conf"
)

group_exists() {
    local group=$1
    for existing_group in "${AVAILABLE_GROUPS[@]}"; do
        if [[ "$existing_group" == "$group" ]]; then
            return 0
        fi
    done
    return 1
}
###########################################
# ФУНКЦИИ
###########################################

# Проверка зависимостей
check_dependencies() {
    local deps=("sed" "cp" "hostname" "mktemp" "date" "grep" "find" "diff")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "Утилита $dep не найдена. Установите недостающие зависимости."
            exit 1
        fi
    done
}

# Инициализация директорий
init_directories() {
    local dirs=(
        "$BASE_CONFIG_DIR"
        "$BASE_BACKUP_DIR"
        "$BASE_LOG_DIR"
        "$TEMP_DIR"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                echo "Не удалось создать директорию: $dir"
                exit 1
            }
            chmod "$SECURE_DIRECTORIES" "$dir"
        fi
    done
}

# Функция логирования
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Проверка размера лог-файла и ротация при необходимости
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt $(numfmt --from=iec $LOG_MAX_SIZE) ]; then
        for i in $(seq $((LOG_ROTATE_COUNT-1)) -1 0); do
            [ -f "${LOG_FILE}.$i" ] && mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))"
        done
        mv "$LOG_FILE" "${LOG_FILE}.0"
    fi

    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ] || [ "$level" = "ERROR" ]; then
        echo "[$level] $message" >&2
    fi
}

# Функция установки блокировки
set_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "ERROR" "Скрипт уже запущен (PID: $pid)"
            exit 1
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

# Функция снятия блокировки
remove_lock() {
    rm -f "$LOCK_FILE"
}

# Функция очистки при завершении
cleanup() {
    remove_lock
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"/*
    fi
    if [ -n "$TEMP_FILE" ] && [ -f "$TEMP_FILE" ]; then
        rm -f "$TEMP_FILE"
    fi
}

list_groups() {
    log "INFO" "Доступные группы:"
    for group in "${AVAILABLE_GROUPS[@]}"; do
        if [[ -f "${SOURCE_CONFIG_PATHS[$group]}" ]]; then
            echo "- $group (конфиг: ${SOURCE_CONFIG_PATHS[$group]})"
        else
            echo "- $group (конфиг отсутствует)"
        fi
    done
}
add_group() {
    local new_group=$1
    local config_path=$2

    if [[ -z "$new_group" || -z "$config_path" ]]; then
        log "ERROR" "Использование: add_group <имя_группы> <путь_к_конфигу>"
        return 1
    fi

    # Проверка существования группы
    if group_exists "$new_group"; then
        log "ERROR" "Группа $new_group уже существует"
        return 1
    fi

    # Добавление новой группы
    AVAILABLE_GROUPS+=("$new_group")
    SOURCE_CONFIG_PATHS["$new_group"]="$config_path"

    # Создание директории для конфига если она не существует
    mkdir -p "$(dirname "$config_path")"
    touch "$config_path"

    # Сохраняем обновленные группы
    save_groups

    log "INFO" "Добавлена новая группа: $new_group с конфигом: $config_path"
}

remove_group() {
    local group=$1

    if [[ -z "$group" ]]; then
        log "ERROR" "Использование: remove_group <имя_группы>"
        return 1
    fi

    # Проверка существования группы
    if ! group_exists "$group"; then
        log "ERROR" "Группа $group не найдена"
        return 1
    fi

    # Удаление группы
    for i in "${!AVAILABLE_GROUPS[@]}"; do
        if [[ "${AVAILABLE_GROUPS[$i]}" == "$group" ]]; then
            unset 'AVAILABLE_GROUPS[$i]'
            break
        fi
    done

    unset "SOURCE_CONFIG_PATHS[$group]"

    # Сохраняем обновленные группы
    save_groups

    log "INFO" "Группа $group удалена"
}

rename_group() {
    local old_name=$1
    local new_name=$2

    if [[ -z "$old_name" || -z "$new_name" ]]; then
        log "ERROR" "Использование: rename_group <старое_имя> <новое_имя>"
        return 1
    fi

    # Проверка существования старой группы и отсутствия новой
    local old_exists=false
    local new_exists=false

    for group in "${AVAILABLE_GROUPS[@]}"; do
        if [[ "$group" == "$old_name" ]]; then
            old_exists=true
        fi
        if [[ "$group" == "$new_name" ]]; then
            new_exists=true
        fi
    done

    if [[ "$old_exists" == false ]]; then
        log "ERROR" "Группа $old_name не существует"
        return 1
    fi

    if [[ "$new_exists" == true ]]; then
        log "ERROR" "Группа $new_name уже существует"
        return 1
    fi

    # Переименование группы
    for i in "${!AVAILABLE_GROUPS[@]}"; do
        if [[ "${AVAILABLE_GROUPS[$i]}" == "$old_name" ]]; then
            AVAILABLE_GROUPS[$i]="$new_name"
            break
        fi
    done

    # Обновление путей конфигурации
    if [[ -n "${SOURCE_CONFIG_PATHS[$old_name]}" ]]; then
        SOURCE_CONFIG_PATHS["$new_name"]="${SOURCE_CONFIG_PATHS[$old_name]}"
        unset "SOURCE_CONFIG_PATHS[$old_name]"
    fi
    # Сохраняем обновленные группы
    save_groups
    log "INFO" "Группа $old_name переименована в $new_name"
}

clone_group() {
    local source_group=$1
    local target_group=$2

    if [[ -z "$source_group" || -z "$target_group" ]]; then
        log "ERROR" "Использование: clone_group <исходная_группа> <целевая_группа>"
        return 1
    fi

    # Проверка существования исходной группы
    if [[ ! " ${AVAILABLE_GROUPS[@]} " =~ " ${source_group} " ]]; then
        log "ERROR" "Исходная группа $source_group не существует"
        return 1
    fi

    # Проверка отсутствия целевой группы
    if [[ " ${AVAILABLE_GROUPS[@]} " =~ " ${target_group} " ]]; then
        log "ERROR" "Целевая группа $target_group уже существует"
        return 1
    fi

    # Создание пути для новой группы
    local source_path="${SOURCE_CONFIG_PATHS[$source_group]}"
    local target_path="${source_path//$source_group/$target_group}"

    # Копирование конфигурации
    mkdir -p "$(dirname "$target_path")"
    cp "$source_path" "$target_path"

    # Добавление новой группы
    AVAILABLE_GROUPS+=("$target_group")
    SOURCE_CONFIG_PATHS["$target_group"]="$target_path"
    # Сохраняем обновленные группы
    save_groups
    log "INFO" "Группа $source_group успешно клонирована в $target_group"
}


# Функции для работы с бэкапами
create_backup() {
    local group=$1
    local timestamp=$(date '+%Y%m%d_%H%M%S')

    # Если группа не указана, используем SERVER_GROUP
    if [[ -z "$group" ]]; then
        group="${SERVER_GROUP:-default}"
    fi

    local backup_dir="${BASE_BACKUP_DIR}/${group}/${timestamp}"

    # Проверка существования группы, если это не 'default'
    if [[ "$group" != "default" ]] && [[ ! " ${AVAILABLE_GROUPS[@]} " =~ " ${group} " ]]; then
        log "ERROR" "Группа $group не существует"
        return 1
    fi

    # Создание директории для бэкапа
    if ! mkdir -p "$backup_dir"; then
        log "ERROR" "Не удалось создать директорию для бэкапа: $backup_dir"
        return 1
    fi

    # Копирование конфигурационных файлов
    local config_path="${SOURCE_CONFIG_PATHS[$group]:-$SOURCE_CONFIG}"
    if [[ -f "$config_path" ]]; then
        if ! cp "$config_path" "$backup_dir/"; then
            log "ERROR" "Не удалось скопировать файл $config_path"
            return 1
        fi
    fi

    for file in "${SEARCH_DIRS[@]}"; do
        if [[ -f "$file" ]]; then
            if ! cp "$file" "$backup_dir/"; then
                log "ERROR" "Не удалось скопировать файл $file"
                return 1
            fi
        fi
    done

    log "INFO" "Создан бэкап группы $group в $backup_dir"
    return 0
}

restore_backup() {
    local group=$1
    local timestamp=$2

    if [[ -z "$group" || -z "$timestamp" ]]; then
        log "ERROR" "Использование: restore_backup <группа> <timestamp>"
        return 1
    fi

    local backup_dir="${BASE_BACKUP_DIR}/${group}/${timestamp}"

    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR" "Бэкап не найден: $backup_dir"
        return 1
    fi

    # Восстановление конфигурационных файлов
    for file in "$backup_dir"/*; do
        local basename=$(basename "$file")
        local target_path

        if [[ -f "${SOURCE_CONFIG_PATHS[$group]}" && "$basename" == $(basename "${SOURCE_CONFIG_PATHS[$group]}") ]]; then
            target_path="${SOURCE_CONFIG_PATHS[$group]}"
        else
            for search_path in "${SEARCH_DIRS[@]}"; do
                if [[ "$basename" == $(basename "$search_path") ]]; then
                    target_path="$search_path"
                    break
                fi
            done
        fi

        if [[ -n "$target_path" ]]; then
            cp "$file" "$target_path"
            log "INFO" "Восстановлен файл: $target_path"
        fi
    done

    log "INFO" "Бэкап группы $group ($timestamp) успешно восстановлен"
}

list_backups() {
    local group=$1

    if [[ -z "$group" ]]; then
        log "ERROR" "Использование: list_backups <группа>"
        return 1
    fi

    local backup_dir="${BASE_BACKUP_DIR}/${group}"

    if [[ ! -d "$backup_dir" ]]; then
        log "INFO" "Бэкапы для группы $group не найдены"
        return 0
    fi

    log "INFO" "Доступные бэкапы для группы $group:"
    for timestamp_dir in "$backup_dir"/*; do
        if [[ -d "$timestamp_dir" ]]; then
            echo "- $(basename "$timestamp_dir")"
        fi
    done
}

cleanup_old_backups() {
    local group=$1
    local days=${2:-30}  # По умолчанию удаляем бэкапы старше 30 дней

    if [[ -z "$group" ]]; then
        log "ERROR" "Использование: cleanup_old_backups <группа> [дни]"
        return 1
    fi

    local backup_dir="${BASE_BACKUP_DIR}/${group}"

    if [[ ! -d "$backup_dir" ]]; then
        log "INFO" "Нет бэкапов для очистки в группе $group"
        return 0
    fi

    find "$backup_dir" -type d -mtime "+$days" -exec rm -rf {} \;
    log "INFO" "Удалены бэкапы группы $group старше $days дней"
}

# Функции для работы с переменными
validate_variables() {
    local file=$1
    local errors=0

    if [[ -z "$file" ]]; then
        file="$SOURCE_CONFIG"
    fi

    while IFS='=' read -r key value; do
        # Пропускаем пустые строки и комментарии
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Очистка от пробелов
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Проверка формата
        if [[ -z "$key" || -z "$value" ]]; then
            log "ERROR" "Неверный формат строки: '$key=$value'"
            ((errors++))
            continue
        fi

        # Проверка специальных символов в ключе
        if [[ "$key" =~ [^a-zA-Z0-9_] ]]; then
            log "ERROR" "Недопустимые символы в ключе: $key"
            ((errors++))
        fi
    done < "$file"

    if [[ $errors -eq 0 ]]; then
        log "INFO" "Все переменные в $file корректны"
        return 0
    else
        log "ERROR" "Найдено $errors ошибок в файле $file"
        return 1
    fi
}

show_variables() {
    local group=$1

    if [[ -n "$group" ]]; then
        if [[ ! " ${AVAILABLE_GROUPS[@]} " =~ " ${group} " ]]; then
            log "ERROR" "Группа $group не существует"
            return 1
        fi
        local config_file="${SOURCE_CONFIG_PATHS[$group]}"
    else
        local config_file="$SOURCE_CONFIG"
    fi

    log "INFO" "Переменные из файла $config_file:"
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        if [[ -n "$key" && -n "$value" ]]; then
            echo "$key = $value"
        fi
    done < "$config_file"
}

diff_variables() {
    local group1=$1
    local group2=$2

    if [[ -z "$group1" || -z "$group2" ]]; then
        log "ERROR" "Использование: diff_variables <группа1> <группа2>"
        return 1
    fi

    if [[ ! " ${AVAILABLE_GROUPS[@]} " =~ " ${group1} " ]]; then
        log "ERROR" "Группа $group1 не существует"
        return 1
    fi

    if [[ ! " ${AVAILABLE_GROUPS[@]} " =~ " ${group2} " ]]; then
        log "ERROR" "Группа $group2 не существует"
        return 1
    fi

    log "INFO" "Сравнение переменных групп $group1 и $group2:"
    diff -u "${SOURCE_CONFIG_PATHS[$group1]}" "${SOURCE_CONFIG_PATHS[$group2]}"
}

search_variable() {
    local pattern=$1
    local group=$2

    if [[ -z "$pattern" ]]; then
        log "ERROR" "Использование: search_variable <паттерн> [группа]"
        return 1
    fi

    if [[ -n "$group" ]]; then
        if [[ ! " ${AVAILABLE_GROUPS[@]} " =~ " ${group} " ]]; then
            log "ERROR" "Группа $group не существует"
            return 1
        fi
        local configs=("${SOURCE_CONFIG_PATHS[$group]}")
    else
        local configs=("${SOURCE_CONFIG_PATHS[@]}")
    fi

    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            log "INFO" "Поиск в $config:"
            grep -n "$pattern" "$config" || true
        fi
    done
}

copy_gold_configs() {
    local group=$1

    # Если группа не указана, используем SERVER_GROUP
    if [[ -z "$group" ]]; then
        group="${SERVER_GROUP:-default}"
    fi

    # Проверяем существование директории GOLD
    if [[ ! -d "$GOLD_CONFIG_DIR" ]]; then
        log "WARNING" "Директория $GOLD_CONFIG_DIR не существует"
        return 0
    fi

    local copied_files=0
    local skipped_files=0

    # Проходим по каждому файлу в GOLD
    for gold_file in "$GOLD_CONFIG_DIR"/*; do
        # Проверяем, что это файл
        if [[ ! -f "$gold_file" ]]; then
            continue
        fi

        local filename=$(basename "$gold_file")
        local target_path="${GOLD_TARGET_PATHS[$filename]}"

        # Проверяем, есть ли для файла целевой путь
        if [[ -z "$target_path" ]]; then
            log "WARNING" "Файл $filename из GOLD не имеет соответствующего места назначения"
            ((skipped_files++))
            continue
        fi

        # Создаем резервную копию существующего файла, если он есть
        if [[ -f "$target_path" ]]; then
            local backup_file="${target_path}.bak.$(date '+%Y%m%d_%H%M%S')"
            cp "$target_path" "$backup_file"
            log "INFO" "Создана резервная копия $target_path как $backup_file"
        fi

        # Копируем файл
        cp "$gold_file" "$target_path"
        log "INFO" "Скопирован файл $filename из GOLD в $target_path"

        ((copied_files++))
    done

    log "INFO" "Обработка файлов из GOLD завершена. Скопировано: $copied_files, пропущено: $skipped_files"
    return 0
}
###########################################
# ОСНОВНАЯ ЛОГИКА
###########################################

# Обработка сигналов
trap cleanup EXIT INT TERM

# Функция вывода справки
show_help() {
    cat << EOF
Использование: $SCRIPT_NAME [ОПЦИИ]
Управление конфигурациями с поддержкой групп серверов.

Основные опции:
    -g GROUP   Указать группу серверов (${AVAILABLE_GROUPS[*]})
    -s FILE    Использовать альтернативный source-файл
    -q         Тихий режим
    -b         Без создания резервных копий
    -d         Dry-run (показать изменения без применения)
    -h         Показать эту справку
    -v         Показать версию

Управление группами:
    --list-groups              Показать список групп
    --add-group NAME PATH      Добавить новую группу
    --remove-group NAME        Удалить группу
    --rename-group OLD NEW     Переименовать группу
    --clone-group SRC DST      Клонировать группу

Управление бэкапами:
    --create-backup GROUP      Создать резервную копию
    --restore-backup GROUP TS  Восстановить из резервной копии
    --list-backups GROUP      Показать список резервных копий
    --cleanup-backups GROUP    Очистить старые резервные копии

Управление переменными:
    --validate [GROUP]         Проверить переменные
    --show-vars [GROUP]        Показать переменные
    --diff-vars GROUP1 GROUP2  Сравнить переменные групп
    --search-var PATTERN       Найти переменную

Примеры:
    $SCRIPT_NAME -g dev                    # Запуск для группы dev
    $SCRIPT_NAME --list-groups              # Показать список групп
    $SCRIPT_NAME --create-backup dev       # Создать бэкап dev
    $SCRIPT_NAME --show-vars dev            # Показать переменные dev
EOF
    exit 0
}
select_config_file() {
    local group=$1
    local custom_source=$2

    # Если передан кастомный source-файл, используем его
    if [[ -n "$custom_source" ]]; then
        if [[ ! -f "$custom_source" ]]; then
            log "ERROR" "Кастомный файл конфигурации не найден: $custom_source"
            exit 1
        fi
        SOURCE_CONFIG="$custom_source"
        return 0
    fi

    # Выбираем источник в зависимости от группы
    if [[ -n "$group" ]]; then
        if [[ -f "${SOURCE_CONFIG_PATHS[$group]}" ]]; then
            SOURCE_CONFIG="${SOURCE_CONFIG_PATHS[$group]}"
        else
            log "WARNING" "Файл конфигурации для группы $group не найден. Используется файл по умолчанию."
            SOURCE_CONFIG="$DEFAULT_SOURCE_CONFIG_PATH"
        fi
    else
        # Если группа не указана, используем дефолтный файл
        SOURCE_CONFIG="$DEFAULT_SOURCE_CONFIG_PATH"
    fi

    # Проверяем существование выбранного файла
    if [[ ! -f "$SOURCE_CONFIG" ]]; then
        log "ERROR" "Конфигурационный файл не найден: $SOURCE_CONFIG"
        exit 1
    fi
}

# Загрузка переменных из source файла
load_variables() {
    while IFS='=' read -r key value; do
        # Пропускаем пустые строки и комментарии
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Очистка от пробелов
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        if [ -n "$key" ] && [ -n "$value" ]; then
            variables[$key]=$value
        fi
    done < "$SOURCE_CONFIG"

    # Обработка HOSTNAME
    if [ -z "${variables[HOSTNAME]}" ] || [ "${variables[HOSTNAME]}" = "default" ]; then
        variables["HOSTNAME"]=$(hostname)
    fi

    # Добавляем группу серверов, если указана
    if [ -n "$SERVER_GROUP" ]; then
        variables["SERVER_GROUP"]="$SERVER_GROUP"
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
# Функция замены переменных
replace_variables() {
    local file=$1
    local group=$2  # Добавляем параметр group

    log "INFO" "Обработка файла: $file"

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY-RUN] Симуляция обработки файла: $file"
        return 0
    fi

    if ! check_permissions "$file"; then
        return 1
    fi

    # Создание резервной копии
    if [ "$BACKUP" = true ]; then
        log "INFO" "Создание бэкапа для группы: $group"
        if ! create_backup "$group"; then
            log "ERROR" "Не удалось создать резервную копию файла: $file"
            return 1
        fi
    fi

    # Создаем временный файл
    local temp_file=$(mktemp)
    cp "$file" "$temp_file"

    # Замена переменных
    for key in "${!variables[@]}"; do
        value="${variables[$key]}"
        search_pattern="\${$key}"
        escaped_value=$(printf '%s\n' "$value" | sed 's:[][\/@\#$.*/&]:\\&:g')
        sed -i "s|$search_pattern|$value|g" "$temp_file"
    done

    # Проверка изменений
    if cmp -s "$temp_file" "$file"; then
        log "INFO" "Никаких изменений для $file"
    else
        cp "$temp_file" "$file"
        log "INFO" "Обновлен файл $file"
    fi

    # Удаляем временный файл
    rm "$temp_file"
}

# Основная функция
main() {
    # Установка блокировки
    set_lock

    # Проверка зависимостей и инициализация
    check_dependencies
    init_directories

    # Загрузка переменных
    load_variables

    # Копирование файлов из GOLD
    copy_gold_configs "$SERVER_GROUP"

    # Обработка файлов
    local found_files=0
    local processed_files=0

    for file in "${SEARCH_DIRS[@]}"; do
        if [ -f "$file" ]; then
            ((found_files++))
            if replace_variables "$file"; then
                ((processed_files++))
            fi
        else
            log "WARNING" "Файл не найден: $file"
        fi
    done

    if [ $found_files -eq 0 ]; then
        log "WARNING" "Не найдено ни одного конфигурационного файла"
    else
        log "INFO" "Обработка завершена. Найдено файлов: $found_files, обработано: $processed_files"
    fi
}

# Парсинг аргументов командной строки и запуск соответствующих функций
while [[ $# -gt 0 ]]; do
    case $1 in
        -g) SERVER_GROUP="$2"; shift 2 ;;
        -s) CUSTOM_SOURCE="$2"; shift 2 ;;
        -q) VERBOSE=false; shift ;;
        -b) BACKUP=false; shift ;;
        -d) DRY_RUN=true; shift ;;
        -h) show_help ;;
        -v) echo "$SCRIPT_NAME версия $VERSION"; exit 0 ;;
        --list-groups) list_groups; exit 0 ;;
        --add-group) add_group "$2" "$3"; exit $?; shift 3 ;;
        --remove-group) remove_group "$2"; exit $?; shift 2 ;;
        --rename-group) rename_group "$2" "$3"; exit $?; shift 3 ;;
        --clone-group) clone_group "$2" "$3"; exit $?; shift 3 ;;
        --create-backup) create_backup "$2"; exit $?; shift 2 ;;
        --restore-backup) restore_backup "$2" "$3"; exit $?; shift 3 ;;
        --list-backups) list_backups "$2"; exit $?; shift 2 ;;
        --cleanup-backups) cleanup_old_backups "$2" "$BACKUP_RETENTION_DAYS"; exit $?; shift 2 ;;
        --validate) validate_variables "$2"; exit $?; shift 2 ;;
        --show-vars) show_variables "$2"; exit $?; shift 2 ;;
        --diff-vars) diff_variables "$2" "$3"; exit $?; shift 3 ;;
        --search-var) search_variable "$2" "$3"; exit $?; shift 3 ;;
        *) echo "Неизвестная опция: $1"; show_help ;;
    esac
done

# Выбор конфигурационного файла
select_config_file "$SERVER_GROUP" "$CUSTOM_SOURCE"

# Запуск основной логики
main

exit 0