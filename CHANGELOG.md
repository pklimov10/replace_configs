▎[1.2.0] - 16.12.2024

▎Добавлено
- Новая функция copy_gold_configs() для копирования эталонных конфигураций
- Поддержка глобальной переменной GOLD_CONFIG_DIR
- Новая константа GOLD_TARGET_PATHS для сопоставления путей копирования

▎Изменено
- Расширена функция main() для интеграции с copy_gold_configs()
- Улучшена обработка групп серверов
- Оптимизирована логика резервного копирования

▎[1.1.0] - 16.12.2024

▎Добавлено
- Функции управления группами:
    - list_groups()
    - add_group()
    - remove_group()
    - rename_group()
    - clone_group()
- Новые параметры командной строки для операций с группами
- Расширенная справка с описанием новых возможностей

▎Улучшено
- Валидация входных параметров
- Обработка ошибок для групповых операций
- Логирование действий

▎[1.0.0] - 15.12.2023

▎Добавлено
- Основной функционал
    - Базовое управление конфигурационными файлами
    - Система резервного копирования
    - Замена переменных в конфигурациях
    - Поддержка различных групп серверов
    - Гибкое логирование
    - Проверка зависимостей
    - Блокировка параллельного выполнения

▎Функции
- Создание и восстановление резервных копий
- Валидация переменных
- Поиск и сравнение переменных
- Тихий режим
- Режим тестового запуска

▎[0.9.0] - 14.12.2023

▎Добавлено
- Предпроизводственная версия
- Начальное тестирование основных механизмов
- Базовая структура скрипта
- Реализация основного функционала
- Базовое логирование и обработка ошибок

▎Планируемые улучшения

▎В будущем
- Поддержка шаблонов конфигурации
- Интеграция с системами управления конфигурациями
- Расширенная валидация и проверка конфигураций
- Поддержка удаленной синхронизации
- Мультиплатформенная совместимость
- Мониторинг изменений конфигурации