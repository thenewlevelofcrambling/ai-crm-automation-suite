// Нода Code в n8n. Mode: "Run Once for All Items".
// Парсит ответ Claude, сливает с данными заявки и НИКОГДА не теряет лид.

// Данные заявки берём из Webhook-ноды (всегда есть).
const lead = $('Webhook').first().json.body;

// Пытаемся распарсить ответ AI. Если AI упал, вернул не-JSON,
// или HTTP-нода передала ошибку (On Error: Continue) — НЕ роняем поток,
// а подставляем безопасные значения, чтобы заявка дошла до менеджера.
let ai;
try {
  ai = JSON.parse($input.first().json.content[0].text);
} catch (e) {
  ai = {
    category: "Не определён",
    priority: "Не определён",
    summary: "AI не смог обработать заявку — нужна ручная проверка.",
    next_step: "Связаться с клиентом вручную",
  };
}

return [{
  json: {
    timestamp: new Date().toISOString(),
    ...lead,
    // Ведущий апостроф: чтобы Sheets не принял "+7..." за формулу (#ERROR!).
    phone: "'" + lead.phone,
    ...ai,
    status: "Новая",
  },
}];
