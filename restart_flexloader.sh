#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader/flexloader"  # Путь к директории с исполняемыми файлами
CURRENT_USER=$(whoami)
MAX_WAIT_TIME=30  # максимальное время ожидания завершения процессов в секундах
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Получаем директорию скрипта
LOG_DIR="$SCRIPT_DIR/logs_restartor"  # Логи храним в папке logs_restartor рядом со скриптом
RESTART_LOG="$LOG_DIR/restart.log"
RUN_DIR="$FLEXLOADER_HOME/run"

# Создаем директорию для логов если её нет
mkdir -p "$LOG_DIR"

# Список процессов для проверки и перезапуска
PROCESSES_TO_CHECK=(
    "meta-init-service"
    "target-init-service"
    "extract-all --daemon"
    "apply-all --daemon"
)

# Функция для логирования
log_message() {
    local message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$RESTART_LOG"
}

# Функция для проверки наличия Java
check_java() {
    if ! command -v java >/dev/null 2>&1; then
        log_message "ОШИБКА: Java не установлена"
        exit 1
    fi
    
    java_version=$(java -version 2>&1 | head -n 1)
    log_message "Используется $java_version"
}

# Функция для проверки наличия jar файла
check_jar() {
    if [ ! -f "$FLEXLOADER_HOME/flexloader.jar" ]; then
        log_message "ОШИБКА: flexloader.jar не найден в $FLEXLOADER_HOME"
        exit 1
    fi
}

# Функция для получения PID и пути процесса
get_process_info() {
    local search_pattern=$1
    ps -ef | grep "$search_pattern" | grep "$CURRENT_USER" | grep "$FLEXLOADER_HOME" | grep -v grep | \
    awk -v home="$FLEXLOADER_HOME" '{
        cmd = "";
        for(i=8; i<=NF; i++) cmd = cmd $i " ";
        if (index(cmd, home) > 0) print $2 "\t" cmd
    }'
}

# Функция для мягкого завершения процесса
stop_process() {
    local process_name=$1
    local process_info
    
    while IFS=$'\t' read -r pid cmd; do
        # Дополнительная проверка пути
        if [[ "$cmd" == *"$FLEXLOADER_HOME"* ]]; then
            log_message "Останавливаем процесс $process_name (PID: $pid)"
            log_message "Команда процесса: $cmd"
            kill -15 "$pid"
            
            # Ждем завершения процесса
            local wait_time=0
            while kill -0 "$pid" 2>/dev/null && [ $wait_time -lt $MAX_WAIT_TIME ]; do
                sleep 1
                wait_time=$((wait_time + 1))
                echo -n "."
            done
            echo ""
            
            # Если процесс все еще работает после таймаута, завершаем принудительно
            if kill -0 "$pid" 2>/dev/null; then
                log_message "ПРЕДУПРЕЖДЕНИЕ: Процесс не завершился за $MAX_WAIT_TIME секунд, выполняем принудительное завершение..."
                kill -9 "$pid"
            else
                log_message "Процесс успешно остановлен"
            fi
        else
            log_message "ПРОПУЩЕНО: Процесс $pid не принадлежит директории $FLEXLOADER_HOME"
        fi
    done < <(get_process_info "$process_name")
}

# Функция проверки и ожидания очистки папки run
wait_for_run_dir_cleanup() {
    local max_wait=300  # максимальное время ожидания в секундах (5 минут)
    local wait_time=0
    local check_interval=5  # интервал проверки в секундах

    log_message "Проверяем папку $RUN_DIR"
    
    if [ ! -d "$RUN_DIR" ]; then
        log_message "Папка $RUN_DIR не существует"
        return 0
    fi

    while [ $wait_time -lt $max_wait ]; do
        local dir_count=$(find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
        
        if [ "$dir_count" -eq 0 ]; then
            log_message "Папка $RUN_DIR пуста"
            return 0
        fi

        log_message "В папке $RUN_DIR найдено $dir_count директорий. Ожидаем их удаления..."
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
        
        # Показываем прогресс
        echo -n "."
    done

    echo ""  # Новая строка после точек
    
    if [ $wait_time -ge $max_wait ]; then
        log_message "ПРЕДУПРЕЖДЕНИЕ: Превышено время ожидания очистки папки $RUN_DIR"
        log_message "Содержимое папки $RUN_DIR:"
        ls -la "$RUN_DIR" | tee -a "$RESTART_LOG"
        return 1
    fi
}

# Добавляем функцию проверки файлов
check_executables() {
    local files=("meta-init-service" "target-init-service" "extract-all" "apply-all")
    
    log_message "Проверяем наличие исполняемых файлов в $FLEXLOADER_HOME"
    ls -la "$FLEXLOADER_HOME" >> "$RESTART_LOG"
    
    for file in "${files[@]}"; do
        if [ ! -f "$FLEXLOADER_HOME/$file" ]; then
            log_message "ОШИБКА: Файл $file не найден в $FLEXLOADER_HOME"
            return 1
        fi
        if [ ! -x "$FLEXLOADER_HOME/$file" ]; then
            log_message "ОШИБКА: Файл $file не является исполняемым"
            return 1
        fi
    done
    
    return 0
}

# Функция для запуска процесса
start_process() {
    local process_name=$1
    local command
    local max_retries=3
    local retry_count=0
    local log_file
    
    case "$process_name" in
        *"meta-init"*)
            command="$FLEXLOADER_HOME/meta-init-service"
            log_file="meta-init-service.log"
            ;;
        *"target-init"*)
            command="$FLEXLOADER_HOME/target-init-service"
            log_file="target-init-service.log"
            ;;
        *"extract-all"*)
            command="$FLEXLOADER_HOME/extract-all --daemon"
            log_file="extract-all.log"
            ;;
        *"apply-all"*)
            command="$FLEXLOADER_HOME/apply-all --daemon"
            log_file="apply-all.log"
            ;;
    esac
    
    log_message "Запускаем $command..."
    
    # Проверяем наличие исполняемого файла
    executable=$(echo $command | cut -d' ' -f1)
    if [ ! -x "$executable" ]; then
        log_message "ОШИБКА: Исполняемый файл $executable не найден или не является исполняемым"
        return 1
    fi
    
    # Попытка запуска с повторами при неудаче
    while [ $retry_count -lt $max_retries ]; do
        log_message "Выполняем команду: $command"
        $command > "$LOG_DIR/$log_file" 2>&1 &
        sleep 5  # увеличили время ожидания до 5 секунд между запусками
        
        if [ -n "$(get_process_info "$process_name" | cut -f1)" ]; then
            log_message "Процесс $command успешно запущен"
            return 0
        else
            retry_count=$((retry_count + 1))
            log_message "Попытка $retry_count из $max_retries запустить процесс $command"
            sleep 5
        fi
    done
    
    log_message "ОШИБКА: Не удалось запустить процесс $command после $max_retries попыток"
    return 1
}

# Функция очистки старых логов
cleanup_logs() {
    local max_log_days=7
    log_message "Очистка логов старше $max_log_days дней..."
    find "$LOG_DIR" -name "*.log" -type f -mtime +$max_log_days -delete
}

# Функция для проверки свободного места
check_disk_space() {
    local min_space=1000000  # минимум 1GB в KB
    local free_space=$(df -k "$FLEXLOADER_HOME" | awk 'NR==2 {print $4}')
    
    if [ "$free_space" -lt "$min_space" ]; then
        log_message "ПРЕДУПРЕЖДЕНИЕ: Мало свободного места на диске (меньше 1GB)"
        return 1
    fi
    return 0
}

# Основной процесс перезапуска
log_message "Начинаем перезапуск процессов Flexloader..."
log_message "----------------------------------------"

# Предварительные проверки
check_java
check_jar
check_disk_space || {
    log_message "Продолжаем несмотря на предупреждение о месте на диске..."
}

# Проверяем наличие исполняемых файлов
if ! check_executables; then
    log_message "ОШИБКА: Не все исполняемые файлы доступны"
    exit 1
fi

# Ожидаем очистки папки run
if ! wait_for_run_dir_cleanup; then
    log_message "ПРЕДУПРЕЖДЕНИЕ: Папка $RUN_DIR не была очищена"
fi

# Останавливаем все процессы
for process in "${PROCESSES_TO_CHECK[@]}"; do
    stop_process "$process"
done

log_message "----------------------------------------"
log_message "Все процессы остановлены"
log_message "Начинаем запуск процессов..."
log_message "----------------------------------------"

# Очистка старых логов перед запуском
cleanup_logs

# Ждем очистки папки run перед запуском новых процессов
log_message "Ожидаем очистки папки $RUN_DIR перед запуском процессов..."
if ! wait_for_run_dir_cleanup; then
    log_message "ОШИБКА: Папка $RUN_DIR не была очищена в установленное время"
    exit 1
fi

# Запускаем все процессы
failed_starts=0
for process in "${PROCESSES_TO_CHECK[@]}"; do
    if ! start_process "$process"; then
        failed_starts=$((failed_starts + 1))
    fi
done

log_message "----------------------------------------"
if [ $failed_starts -eq 0 ]; then
    log_message "Перезапуск успешно завершен"
else
    log_message "Перезапуск завершен с ошибками: $failed_starts процессов не удалось запустить"
fi
