#!/bin/bash

# Определение переменных окружения
FLEXLOADER_HOME="/opt/flexloader"  # Измените на нужный путь
FLEXLOADER_VERSIONS_DIR="/opt/flexloader/versions"  # Измените на нужный путь

# Проверка наличия переменных окружения
if [ -z "$FLEXLOADER_HOME" ] || [ -z "$FLEXLOADER_VERSIONS_DIR" ]; then
    echo "Ошибка: Необходимо установить переменные окружения FLEXLOADER_HOME и FLEXLOADER_VERSIONS_DIR"
    exit 1
fi

# Функция для проверки статуса процесса
check_process() {
    local process_name=$1
    ps -f -u $(whoami) | grep "$process_name" | grep -v grep
}

# Функция для получения последних строк лога
get_last_log_lines() {
    local log_file=$1
    if [ -f "$log_file" ]; then
        echo "Последние строки лога:"
        tail -n 5 "$log_file"
    else
        echo "Лог файл не найден: $log_file"
    fi
}

# Поиск нового JAR файла в текущей директории
NEW_VERSION=$(ls -1 ru.glowbyte.flexloader_*.jar 2>/dev/null | head -n 1)

if [ -z "$NEW_VERSION" ]; then
    echo "Ошибка: Новая версия Flexloader не найдена в текущей директории"
    exit 1
fi

# Вывод информации о новой версии
echo "Найдена новая версия Flexloader:"
echo "Файл: $NEW_VERSION"
echo "Версия: $(echo $NEW_VERSION | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+.*\.jar')"

# Запрос подтверждения
read -p "Продолжить обновление? (да/нет): " CONTINUE
if [ "$CONTINUE" != "да" ]; then
    echo "Обновление отменено"
    exit 0
fi

# Проверка работающих процессов
echo "Проверка работающих процессов..."
PROCESSES_TO_CHECK=(
    "ru.glowbyte.flexloader.CLI extract-all"
    "ru.glowbyte.flexloader.CLI meta-init"
    "ru.glowbyte.flexloader.CLI target-init"
    "ru.glowbyte.flexloader.CLI apply-all"
)

for process in "${PROCESSES_TO_CHECK[@]}"; do
    if check_process "$process"; then
        echo "Останавливаем процесс: $process"
        pkill -f "$process"
    fi
done

# Ожидание остановки процессов
echo "Ожидание остановки процессов..."
sleep 5

# Обновление файлов
echo "Начинаем процесс обновления..."
cd "$FLEXLOADER_VERSIONS_DIR"

# Удаление старого симлинка
if [ -L "flexloader.jar" ]; then
    rm flexloader.jar
fi

# Копирование новой версии
cp "$PWD/$NEW_VERSION" .
chmod 744 "$NEW_VERSION"

# Создание нового симлинка
ln -s "$NEW_VERSION" flexloader.jar

# Переход в корневую папку flexloader
cd "$FLEXLOADER_HOME"

# Функция запуска сервиса
start_service() {
    local command=$1
    local service_name=$2
    
    echo "Запуск $service_name..."
    # Запускаем команду и сохраняем вывод
    local output
    output=$($command 2>&1)
    echo "$output"
    
    # Ищем путь к лог файлу в выводе команды (предполагаем, что путь содержит .log)
    local log_file
    log_file=$(echo "$output" | grep -o '[[:alnum:]/_.-]*\.log[[:alnum:]]*')
    
    if [ -n "$log_file" ]; then
        echo "Найден лог файл: $log_file"
        echo "Последние 5 строк лога:"
        tail -n 5 "$log_file"
    else
        echo "Путь к лог файлу не найден в выводе команды"
    fi
    
    sleep 5
    echo "Статус запуска $service_name: Запущен"
    echo "----------------------------------------"
}

# Запуск сервисов
start_service "./meta.init-service" "meta-init"
start_service "./target.init-service" "target-init"
start_service "./extract_all --daemon" "extract-all"
start_service "./apply-all --daemon" "apply-all"

echo "Обновление завершено успешно!"
