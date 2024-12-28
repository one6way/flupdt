#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader"  # Измените на нужный путь
CURRENT_USER=$(whoami)

# Функция для проверки и вывода процесса
check_process() {
    local search_pattern=$1
    local service_type
    
    # Определяем тип сервиса из шаблона поиска
    if [[ $search_pattern == *"extract-all"* ]]; then
        service_type="extract-all"
    elif [[ $search_pattern == *"meta-init"* ]]; then
        service_type="meta-init"
    elif [[ $search_pattern == *"target-init"* ]]; then
        service_type="target-init"
    elif [[ $search_pattern == *"apply-all"* ]]; then
        service_type="apply-all"
    else
        service_type="unknown"
    fi
    
    # Используем wc -l для подсчета строк и избегания пустого вывода
    local count=$(ps -ef | grep "$search_pattern" | grep "$CURRENT_USER" | grep "$FLEXLOADER_HOME" | grep -v grep | wc -l)
    
    if [ "$count" -gt 0 ]; then
        ps -ef | grep "$search_pattern" | grep "$CURRENT_USER" | grep "$FLEXLOADER_HOME" | grep -v grep | \
        while read -r user pid ppid rest; do
            printf "%-20s %-15s %-15s %-8s\n" "$FLEXLOADER_HOME" "$CURRENT_USER" "$service_type" "$pid"
        done
    fi
}

# Список процессов для проверки
PROCESSES_TO_CHECK=(
    "ru.glowbyte.flexloader.CLI extract-all"
    "ru.glowbyte.flexloader.CLI meta-init-service"
    "ru.glowbyte.flexloader.CLI target-init-service"
    "ru.glowbyte.flexloader.CLI apply-all"
)

# Вывод заголовка с тем же форматированием
printf "%-20s %-15s %-15s %-8s\n" "ПАПКА" "ПОЛЬЗОВАТЕЛЬ" "ПРОЦЕСС" "PID"
printf "%s\n" "$(printf '%.0s-' {1..60})"

# Проверка каждого процесса
for process in "${PROCESSES_TO_CHECK[@]}"; do
    check_process "$process"
done
