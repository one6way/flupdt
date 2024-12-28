#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader"  # Измените на нужный путь

# Функция для проверки и вывода PID процесса
check_process() {
    local process_name=$1
    ps -f -u $(whoami) | grep "$FLEXLOADER_HOME" | grep "$process_name" | grep -v grep | awk '{print $2 "\t" $NF}'
}

# Список процессов для проверки
PROCESSES_TO_CHECK=(
    "ru.glowbyte.flexloader.CLI extract-all"
    "ru.glowbyte.flexloader.CLI meta-init"
    "ru.glowbyte.flexloader.CLI target-init"
    "ru.glowbyte.flexloader.CLI apply-all"
)

echo "PID\tПуть"
echo "-------------------"

# Проверка каждого процесса
for process in "${PROCESSES_TO_CHECK[@]}"; do
    check_process "$process"
done
