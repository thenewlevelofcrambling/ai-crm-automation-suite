# AI CRM Automation Suite

![n8n](https://img.shields.io/badge/n8n-orchestration-EA4B71)
![Claude](https://img.shields.io/badge/Claude-Haiku%204.5-D97757)
![Google Sheets](https://img.shields.io/badge/Google%20Sheets-CRM-34A853)
![Telegram](https://img.shields.io/badge/Telegram-notifications-26A5E4)
![RAG](https://img.shields.io/badge/RAG-Mistral%20embeddings-5A67D8)
![Docker](https://img.shields.io/badge/Docker-self--hosted-2496ED)

Система автоматической обработки входящих заявок на базе AI: принимает заявку,
**анализирует её LLM**, заносит в CRM, мгновенно уведомляет менеджера, строит дашборд
и отвечает на вопросы клиентов по базе знаний (RAG).

---

## Проблема, которую решает

Бизнес с потоком заявок из разных каналов теряет деньги на **скорости первого ответа**:
горячий лид остывает, пока менеджер доберётся до него вручную. Плюс — ручной ввод
(ошибки), нет приоритизации (VIP лежит рядом со спамом), данные разрознены.

**Главная ценность системы:** мгновенная реакция на горячие лиды + автоматическая
приоритизация → выше конверсия.

---

## Архитектура

```
[HTML-форма]
     │ POST (+ секретный заголовок)
     ▼
[n8n Webhook]  ── вход, Header-Auth защита
     ▼
[Claude API]   ── классификация: category / priority / summary / next_step (строгий JSON)
     ▼
[Code: parse + merge]  ── разбор JSON, объединение с данными заявки, graceful degradation
     ▼
[Google Sheets]  ── CRM-хранилище
     ▼
[Telegram]       ── мгновенное уведомление менеджеру

[Looker Studio]  ── дашборд (конверсия, приоритеты) — читает Sheets
[RAG-бот]        ── вопросы по базе знаний: Mistral-эмбеддинги + векторный поиск + Claude
```

---

## Стек и осознанные трейд-оффы

| Компонент | Выбор | Почему / пределы |
|---|---|---|
| Оркестрация | **n8n** (self-host, Docker) | Быстрый MVP, видимый поток. На больших нагрузках — код. |
| LLM-анализ | **Claude (claude-haiku-4-5)** | Right-sizing: классификация — простая задача, Haiku дешевле/быстрее Opus в 5 раз. |
| Хранилище | **Google Sheets** | Бесплатно, наглядно. Не БД: нет транзакций, гонки при конкурентной записи → на проде Postgres/Airtable. |
| Уведомления | **Telegram Bot API** | Мгновенный push, менеджер уже там. |
| Дашборд | **Looker Studio** | Бесплатно, нативно к Sheets. |
| Эмбеддинги | **Mistral (mistral-embed)** | Claude не делает эмбеддинги; Mistral доступен и дёшев. |
| Векторное хранилище | **n8n In-Memory** | Для MVP; теряется при рестарте → прод: Qdrant/Supabase/pgvector. |

---

## Ключевые инженерные решения

- **Структурированный вывод (JSON-схема).** AI отдаёт строгий JSON (`output_config.format`),
  а не свободный текст — это надёжный мост между «AI понял» и «автоматизация записала».
- **Right-sizing модели.** Берём самую дешёвую модель, что надёжно решает задачу.
- **Graceful degradation.** `try/catch` при парсинге + `On Error: Continue` на HTTP —
  сбой AI **не теряет лид**: заявка всё равно падает в CRM с `priority: Не определён`.
- **Безопасность вебхука.** Header Auth (общий секрет) → чужие запросы получают 403.
- **Least privilege.** Доступ к Sheets через Service Account, расшаренный только на одну таблицу.
- **Наблюдаемость.** Диагностика через вкладку Executions, а не догадки.

---

## Известные ограничения / next steps

- **Идемпотентность:** двойная отправка формы создаёт дубль. Решение — ключ идемпотентности
  (`hash(email+message)`) + проверка существования перед записью.
- **Race condition при записи в Sheets:** конкурентные Append затирают строки. Решение —
  последовательная обработка / очередь / БД с транзакциями.
- **Векторное хранилище в памяти:** перейти на постоянную векторную БД.
- **Секрет в клиентской форме виден:** в проде форму обслуживает сервер (Tally/бэкенд),
  хранящий секрет, либо подпись запроса.

---

## Структура репозитория

| Файл / папка | Что это |
|---|---|
| `docker-compose.yml` | Поднять n8n (self-host) |
| `workflows/` | Экспорт n8n: `crm-pipeline`, `rag-indexing`, `rag-chatbot` — импортировать в n8n |
| `claude-request-body.json` | Тело запроса к Claude (строгий JSON через `output_config.format`) |
| `parse-code-node.js` | Парсинг ответа AI + merge с заявкой + graceful degradation |
| `knowledge-base.md` | База знаний для RAG-бота |
| `lead-form.html` | Демо-форма заявки (шлёт секретный заголовок) |
| `.env.example` | Шаблон переменных окружения (реальный `.env` в git не попадает) |

> Credentials (Anthropic, Google Service Account, Telegram, Mistral) и `n8n-data/`
> в репозиторий **не входят** — настраиваются локально.

## Демо (локальный запуск)

1. `docker compose up -d` — поднимает n8n на `localhost:5678`.
2. Импортировать workflow'ы (CRM-пайплайн, RAG-индексация, RAG-чат).
3. Настроить credentials: Anthropic, Google Service Account, Telegram, Mistral.
4. Открыть `lead-form.html`, отправить заявку → строка в Sheets + уведомление в Telegram.
5. Дашборд — в Looker Studio поверх таблицы. RAG-бот — чат в n8n.

## Лицензия

MIT
