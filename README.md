# Скрипт обновления Flexloader

Этот скрипт предназначен для автоматизации процесса обновления Flexloader. Он выполняет безопасное обновление версии, создание резервных копий и проверку работоспособности сервисов.

## Основные функции

### 1. Проверка и подготовка
- Проверяет наличие новой версии JAR файла в директории скрипта
- Извлекает и отображает версию из JAR файла
- Запрашивает подтверждение перед обновлением

### 2. Управление процессами
- Находит и останавливает текущие процессы Flexloader
- Проверяет процессы:
  - extract-all
  - meta-init
  - target-init
  - apply-all

### 3. Резервное копирование
- Создает резервную копию текущей версии с меткой времени
- Сохраняет как JAR файл, так и симлинк
- Автоматически очищает старые резервные копии (хранит последние 5)

### 4. Обновление
- Удаляет старый симлинк
- Копирует новую версию JAR файла
- Устанавливает правильные права доступа (744)
- Создает новый симлинк

### 5. Запуск сервисов
- Последовательно запускает все необходимые сервисы
- Отслеживает логи запуска
- Проверяет статус каждого сервиса
- Делает несколько попыток проверки работоспособности

## Требования
- Переменные окружения (задаются в скрипте):
  - FLEXLOADER_HOME: корневая папка Flexloader
  - FLEXLOADER_VERSIONS_DIR: папка с версиями Flexloader

## Использование

1. Положите новую версию JAR файла в директорию со скриптом
2. Запустите скрипт:
   ```bash
   ./update_flexloader.sh
   ```
3. Подтвердите обновление когда скрипт спросит

## Безопасность
- Скрипт не требует прав root
- Создает резервные копии перед обновлением
- Проверяет работоспособность после обновления
- Позволяет быстро откатиться к предыдущей версии

## Логи и мониторинг
- Отслеживает логи всех сервисов
- Показывает последние 5 строк каждого лога
- Проверяет статус запуска каждого сервиса
- Делает несколько попыток проверки перед сообщением об ошибке
