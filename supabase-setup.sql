-- Supabase setup для векторного хранилища RAG (pgvector + Mistral embeddings)
-- Выполнить один раз в Supabase → SQL Editor.
--
-- ВАЖНО: vector(1024) — потому что Mistral (mistral-embed) выдаёт эмбеддинг
-- длиной ровно 1024 числа. Размерность колонки ОБЯЗАНА совпадать с моделью.
-- Сменишь модель эмбеддингов → поменяй и 1024 здесь и в match_documents.

-- 1. Включаем расширение pgvector (учит Postgres хранить вектора и считать близость)
create extension if not exists vector;

-- 2. Таблица для кусков базы знаний + их эмбеддингов
create table if not exists documents (
  id        bigserial primary key,
  content   text,            -- кусок текста (chunk) из knowledge-base.md
  metadata  jsonb,           -- источник / доп. инфо
  embedding vector(1024)     -- эмбеддинг этого куска (Mistral = 1024 dims)
);

-- 3. Функция поиска по близости векторов.
--    Это и есть "retrieval" в RAG: находит куски, чей вектор ближе всего к вопросу.
--    Имя функции (match_documents) n8n использует как queryName.
create or replace function match_documents (
  query_embedding vector(1024),
  match_count int default 5,
  filter jsonb default '{}'
) returns table (
  id         bigint,
  content    text,
  metadata   jsonb,
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    documents.id,
    documents.content,
    documents.metadata,
    1 - (documents.embedding <=> query_embedding) as similarity  -- <=> = косинусное расстояние
  from documents
  where documents.metadata @> filter
  order by documents.embedding <=> query_embedding                -- ближайшие сверху
  limit match_count;
end;
$$;

-- 4. Индекс для скорости поиска на больших объёмах (опционально, но грамотно)
create index if not exists documents_embedding_idx
  on documents using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

-- 5. Row Level Security: запрещаем доступ публичным ключам (anon/authenticated).
--    n8n ходит через service_role, который RLS ИГНОРИРУЕТ → бот работает,
--    а посторонние с публичным ключом к таблице не подберутся.
--    Политики не нужны: прямого публичного доступа к documents нет.
alter table documents enable row level security;
