#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader"  # Измените на нужный путь
CURRENT_USER=$(whoami)

# Функция для получения короткого имени процесса
get_short_name() {
    local full_name=$1
    case $full_name in
        *"extract-all"*) echo "extract-all" ;;
        *"meta-init"*) echo "meta-init" ;;
        *"target-init"*) echo "target-init" ;;
        *"apply-all"*) echo "apply-all" ;;
        *) echo "$full_name" ;;
    esac
}

# Функция для проверки и вывода процесса
check_process() {
    local process_name=$1
    ps -ef | grep "$process_name" | grep "$CURRENT_USER" | grep "$FLEXLOADER_HOME" | grep -v grep | \
    while read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{for(i=8;i<=NF;i++) printf "%s ", $i}')
        short_name=$(get_short_name "$cmd")
        echo -e "$FLEXLOADER_HOME\t$CURRENT_USER\t$short_name\t$pid"
    done
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
