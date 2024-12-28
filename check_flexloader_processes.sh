#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader"  # Измените на нужный путь

# Функция для проверки и вывода PID процесса
check_process() {
    local process_name=$1
    echo "Поиск процесса: $process_name"
    ps -f -u $(whoami) | grep "$FLEXLOADER_HOME" | grep "$process_name" | grep -v grep | while read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        echo "  PID: $pid"
        echo "  Полная команда: $line"
        echo "------------------------"
    done
}

# Список процессов для проверки
PROCESSES_TO_CHECK=(
    "ru.glowbyte.flexloader.CLI extract-all"
    "ru.glowbyte.flexloader.CLI meta-init"
    "ru.glowbyte.flexloader.CLI target-init"
    "ru.glowbyte.flexloader.CLI apply-all"
)

echo "=== Поиск процессов Flexloader ==="
echo "Директория поиска: $FLEXLOADER_HOME"
echo "------------------------"

# Проверка каждого процесса
for process in "${PROCESSES_TO_CHECK[@]}"; do
    check_process "$process"
done

echo "=== Поиск завершен ==="
