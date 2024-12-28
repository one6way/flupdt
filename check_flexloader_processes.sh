#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader"  # Измените на нужный путь
CURRENT_USER=$(whoami)

# Функция для проверки и вывода процесса
check_process() {
    local process_name=$1
    ps -ef | grep "$process_name" | grep "$CURRENT_USER" | grep "$FLEXLOADER_HOME" | grep -v grep | \
    awk -v home="$FLEXLOADER_HOME" -v user="$CURRENT_USER" \
        '{print home "\t" user "\t" $8 "\t" $2}'
}

# Список процессов для проверки
PROCESSES_TO_CHECK=(
    "ru.glowbyte.flexloader.CLI extract-all"
    "ru.glowbyte.flexloader.CLI meta-init-service"
    "ru.glowbyte.flexloader.CLI target-init-service"
    "ru.glowbyte.flexloader.CLI apply-all"
)

echo -e "ПАПКА\tПОЛЬЗОВАТЕЛЬ\tПРОЦЕСС\tPID"
echo "----------------------------------------"

# Проверка каждого процесса
for process in "${PROCESSES_TO_CHECK[@]}"; do
    check_process "$process"
done
