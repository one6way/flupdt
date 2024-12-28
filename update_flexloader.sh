#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader"  # Измените на нужный путь
FLEXLOADER_VERSIONS_DIR="/opt/flexloader/versions"  # Измените на нужный путь
FLEXLOADER_BACKUP_DIR="$(dirname "$0")/backups"  # Папка для бэкапов в директории со скриптом
DEBUG_LOG_FILE="$(dirname "$0")/debug.log"  # Файл для отладочных сообщений

# Функция для логирования
log_debug() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$DEBUG_LOG_FILE"
}

# Создаем новый лог файл
echo "=== Начало выполнения скрипта $(date '+%Y-%m-%d %H:%M:%S') ===" > "$DEBUG_LOG_FILE"

# Создаем директорию для бэкапов, если её нет
log_debug "Создание директории для бэкапов: $FLEXLOADER_BACKUP_DIR"
mkdir -p "$FLEXLOADER_BACKUP_DIR"

# Проверка наличия переменных окружения
log_debug "Проверка переменных окружения"
if [ -z "$FLEXLOADER_HOME" ] || [ -z "$FLEXLOADER_VERSIONS_DIR" ]; then
    log_debug "ОШИБКА: Отсутствуют необходимые переменные окружения"
    echo "Ошибка: Необходимо установить переменные окружения FLEXLOADER_HOME и FLEXLOADER_VERSIONS_DIR"
    exit 1
fi

# Функция для проверки статуса процесса
check_process() {
    local process_name=$1
    log_debug "Проверка процесса: $process_name в директории $FLEXLOADER_HOME"
    # Ищем процессы только от текущего пользователя и только в директории FLEXLOADER_HOME
    ps -f -u $(whoami) | grep "$FLEXLOADER_HOME" | grep "$process_name" | grep -v grep
}

# Функция для получения последних строк лога
get_last_log_lines() {
    local log_file=$1
    log_debug "Чтение последних строк лога: $log_file"
    if [ -f "$log_file" ]; then
        echo "Последние строки лога:"
        tail -n 5 "$log_file"
    else
        log_debug "ОШИБКА: Лог файл не найден: $log_file"
        echo "Лог файл не найден: $log_file"
    fi
}

# Функция для извлечения версии из имени файла
get_version_from_filename() {
    local jar_file=$1
    log_debug "Извлечение версии из файла: $jar_file"
    # Извлекаем версию из имени файла (например, из ru.glowbyte.flexloader_1.2.3.jar получаем 1.2.3)
    echo "$jar_file" | sed -n 's/.*flexloader_\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\.jar$/\1/p'
}

# Функция для создания бэкапа текущей версии
backup_current_version() {
    local backup_dir="$FLEXLOADER_BACKUP_DIR/$(date +%Y%m%d_%H%M%S)"
    log_debug "Создание резервной копии в директории: $backup_dir"
    echo "Создание резервной копии текущей версии..."
    mkdir -p "$backup_dir"
    if [ -L "$FLEXLOADER_VERSIONS_DIR/flexloader.jar" ]; then
        log_debug "Копирование симлинка и JAR файла"
        cp -P "$FLEXLOADER_VERSIONS_DIR/flexloader.jar" "$backup_dir/"
        cp "$(readlink -f "$FLEXLOADER_VERSIONS_DIR/flexloader.jar")" "$backup_dir/"
        echo "Бэкап создан в: $backup_dir"
    else
        log_debug "ОШИБКА: Текущий симлинк не найден"
        echo "Текущий симлинк не найден"
    fi
}

# Функция для проверки здоровья сервиса
check_service_health() {
    local service_name=$1
    local max_retries=3
    local retry=0
    
    log_debug "Начало проверки здоровья сервиса: $service_name"
    while [ $retry -lt $max_retries ]; do
        if ps -f -u $(whoami) | grep "$FLEXLOADER_HOME" | grep "$service_name" | grep -v grep > /dev/null; then
            log_debug "Сервис $service_name успешно запущен"
            echo "Сервис $service_name успешно запущен в $FLEXLOADER_HOME"
            return 0
        fi
        retry=$((retry + 1))
        log_debug "Попытка $retry: Сервис $service_name не запущен"
        echo "Попытка $retry из $max_retries: Сервис $service_name не запущен в $FLEXLOADER_HOME"
        sleep 5
    done
    
    log_debug "ОШИБКА: Сервис $service_name не запустился после $max_retries попыток"
    echo "ОШИБКА: Сервис $service_name не запустился после $max_retries попыток"
    return 1
}

# Функция для очистки старых бэкапов
cleanup_old_backups() {
    local max_backups=5
    
    log_debug "Начало очистки старых бэкапов (оставляем последние $max_backups)"
    if [ -d "$FLEXLOADER_BACKUP_DIR" ]; then
        echo "Очистка старых резервных копий..."
        cd "$FLEXLOADER_BACKUP_DIR" && ls -t | tail -n +$((max_backups + 1)) | xargs -r rm -rf
        log_debug "Очистка завершена"
    fi
}

# Поиск нового JAR файла в текущей директории
log_debug "Поиск новой версии JAR файла"
NEW_VERSION=$(ls -1 ru.glowbyte.flexloader_*.jar 2>/dev/null | head -n 1)

if [ -z "$NEW_VERSION" ]; then
    log_debug "ОШИБКА: Новая версия не найдена"
    echo "Ошибка: Новая версия Flexloader не найдена в текущей директории"
    exit 1
fi

# Вывод информации о новой версии
log_debug "Найден файл: $NEW_VERSION"
echo "Найдена новая версия Flexloader:"
echo "Файл: $NEW_VERSION"
VERSION=$(get_version_from_filename "$NEW_VERSION")
log_debug "Определена версия: $VERSION"
echo "Версия: $VERSION"

# Запрос подтверждения
read -p "Продолжить обновление? (да/нет): " CONTINUE
log_debug "Ответ пользователя: $CONTINUE"
if [ "$CONTINUE" != "да" ]; then
    log_debug "Обновление отменено пользователем"
    echo "Обновление отменено"
    exit 0
fi

# Проверка работающих процессов
log_debug "Начало проверки работающих процессов"
echo "Проверка работающих процессов..."
PROCESSES_TO_CHECK=(
    "ru.glowbyte.flexloader.CLI extract-all"
    "ru.glowbyte.flexloader.CLI meta-init"
    "ru.glowbyte.flexloader.CLI target-init"
    "ru.glowbyte.flexloader.CLI apply-all"
)

for process in "${PROCESSES_TO_CHECK[@]}"; do
    log_debug "Проверка процесса: $process"
    echo "Проверка процесса: $process в директории $FLEXLOADER_HOME"
    if check_process "$process"; then
        log_debug "Остановка процесса: $process"
        echo "Останавливаем процесс: $process"
        pkill -f "$process"
    fi
done

# Ожидание остановки процессов
log_debug "Ожидание остановки процессов"
echo "Ожидание остановки процессов..."
sleep 5

# Обновление файлов
log_debug "Начало процесса обновления"
echo "Начинаем процесс обновления..."
cd "$FLEXLOADER_VERSIONS_DIR"
log_debug "Текущая директория: $FLEXLOADER_VERSIONS_DIR"

# Удаление старого симлинка
if [ -L "flexloader.jar" ]; then
    log_debug "Удаление старого симлинка"
    rm flexloader.jar
fi

# Копирование новой версии
log_debug "Копирование новой версии: $NEW_VERSION"
cp "$PWD/$NEW_VERSION" .
chmod 744 "$NEW_VERSION"
log_debug "Установлены права доступа 744"

# Создание нового симлинка (с принудительной заменой если существует)
log_debug "Создание симлинка: $NEW_VERSION -> flexloader.jar"
ln -sf "$NEW_VERSION" flexloader.jar

# Переход в корневую папку flexloader
cd "$FLEXLOADER_HOME"
log_debug "Переход в директорию: $FLEXLOADER_HOME"

# Функция запуска сервиса
start_service() {
    local command=$1
    local service_name=$2
    
    log_debug "Запуск сервиса: $service_name командой: $command"
    echo "Запуск $service_name..."
    # Запускаем команду и сохраняем вывод
    local output
    output=$($command 2>&1)
    echo "$output"
    log_debug "Вывод команды: $output"
    
    # Ищем путь к лог файлу в выводе команды
    local log_file
    log_file=$(echo "$output" | grep -o '[[:alnum:]/_.-]*\.log[[:alnum:]]*')
    
    if [ -n "$log_file" ]; then
        log_debug "Найден лог файл: $log_file"
        echo "Найден лог файл: $log_file"
        echo "Последние 5 строк лога:"
        tail -n 5 "$log_file"
    else
        log_debug "Путь к лог файлу не найден в выводе команды"
        echo "Путь к лог файлу не найден в выводе команды"
    fi
    
    sleep 5
    log_debug "Статус запуска $service_name: Запущен"
    echo "Статус запуска $service_name: Запущен"
    echo "----------------------------------------"
}

# Запуск сервисов
log_debug "Начало запуска сервисов"
start_service "./meta.init-service" "meta-init"
start_service "./target.init-service" "target-init"
start_service "./extract_all --daemon" "extract-all"
start_service "./apply-all --daemon" "apply-all"

# Проверка здоровья сервисов
log_debug "Начало проверки здоровья сервисов"
check_service_health "meta-init"
check_service_health "target-init"
check_service_health "extract-all"
check_service_health "apply-all"

# Очистка старых бэкапов
cleanup_old_backups

# Создание бэкапа текущей версии
backup_current_version

log_debug "=== Завершение выполнения скрипта $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Обновление завершено успешно!"
