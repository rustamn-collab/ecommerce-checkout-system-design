# API-контракты: Корзина и оформление заказа

Документ описывает REST API для взаимодействия Frontend с микросервисами корзины и чекаута. Все запросы идут через API Gateway. Формат данных — JSON. Аутентификация — Bearer-токен в заголовке `Authorization`.

**Базовый URL:** `https://api.example.com/api/v1`

---

## 1. Расчёт корзины

**`POST /cart/calculate`**

**Назначение:** получить актуальную стоимость корзины с учётом доставки. Проверяет остатки на складе через ERP, запрашивает варианты доставки у Logistics Service.

### Request

```json
{
  "user_id": "3f8a1b2c-4d5e-6f7a-8b9c-0d1e2f3a4b5c",
  "items": [
    {
      "product_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
      "quantity": 2
    },
    {
      "product_id": "b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e",
      "quantity": 1
    }
  ],
  "delivery": {
    "address": {
      "city": "Набережные Челны",
      "street": "Проспект Мира",
      "house": "10",
      "postal_code": "423800"
    }
  }
}
```
### Response 200 (успех)
```json
{
  "cart_id": "c1d2e3f4-a5b6-7c8d-9e0f-1a2b3c4d5e6f",
  "items": [
    {
      "product_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
      "name": "Стол письменный",
      "quantity": 2,
      "price": 5990.00,
      "total": 11980.00,
      "available": true,
      "warehouse_id": "w1w2w3w4-x5y6-7z8a-9b0c-1d2e3f4a5b6c"
    }
  ],
  "subtotal": 11980.00,
  "delivery": {
    "amount": 490.00,
    "currency": "RUB",
    "slots": [
      {
        "id": "s1s2s3s4-t5u6-7v8w-9x0y-1z2a3b4c5d6e",
        "start": "2026-10-08T10:00:00Z",
        "end": "2026-10-08T14:00:00Z",
        "price": 490.00
      },
      {
        "id": "s2s3s4s5-u6v7-8w9x-0y1z-2a3b4c5d6e7f",
        "start": "2026-10-08T14:00:00Z",
        "end": "2026-10-08T18:00:00Z",
        "price": 590.00
      }
    ]
  },
  "total": 12470.00,
  "currency": "RUB",
  "reservation_available": true
}
```
### Response 409 (товара нет в наличии)
```json
{
  "error": "OUT_OF_STOCK",
  "message": "Товар 'Стол письменный' отсутствует на складе",
  "details": {
    "product_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "requested": 2,
    "available": 0,
    "alternative_warehouses": [
      {
        "warehouse_id": "w9w8w7w6-x5y4-3z2a-1b0c-9d8e7f6a5b4c",
        "available": 3,
        "delivery_days": 5
      }
    ]
  }
}
```
### Response 400 (ошибка валидации)
```json
{
  "error": "VALIDATION_ERROR",
  "message": "Некорректный адрес доставки",
  "details": {
    "field": "delivery.address.postal_code",
    "reason": "Неверный формат индекса"
  }
}
```
## 2. Подтверждение заказа
**`POST /checkout/confirm`**

**Назначение:** создать заказ, зарезервировать товар на 15 минут и инициировать оплату через Payment Gateway.

### Request
```json
{
  "user_id": "3f8a1b2c-4d5e-6f7a-8b9c-0d1e2f3a4b5c",
  "cart_id": "c1d2e3f4-a5b6-7c8d-9e0f-1a2b3c4d5e6f",
  "delivery": {
    "address": {
      "city": "Набережные Челны",
      "street": "Проспект Мира",
      "house": "10",
      "postal_code": "423800"
    },
    "slot_id": "s1s2s3s4-t5u6-7v8w-9x0y-1z2a3b4c5d6e"
  },
  "payment": {
    "method": "CARD"
  }
}
```
### Response 201 (заказ создан, ожидает оплаты)
```json
{
  "order_id": "o1o2o3o4-p5q6-7r8s-9t0u-1v2w3x4y5z6a",
  "status": "PENDING_PAYMENT",
  "total": 12470.00,
  "currency": "RUB",
  "payment_url": "https://payment.gateway/checkout/abc123xyz",
  "reservation_expires_at": "2026-10-07T12:15:00Z"
}
```
### Response 400 (ошибка валидации)
```json
{
  "error": "VALIDATION_ERROR",
  "message": "Некорректный адрес доставки",
  "details": {
    "field": "delivery.address.postal_code",
    "reason": "Неверный формат индекса"
  }
}
```
### Response 409 (слот недоступен)
```json
{
  "error": "SLOT_UNAVAILABLE",
  "message": "Выбранный интервал доставки больше недоступен",
  "available_slots": [
    {
      "id": "s2s3s4s5-u6v7-8w9x-0y1z-2a3b4c5d6e7f",
      "start": "2026-10-09T10:00:00Z",
      "end": "2026-10-09T14:00:00Z",
      "price": 490.00
    }
  ]
}
```
### Response 409 (товара не хватило при резервировании)
```json
{
  "error": "RESERVATION_FAILED",
  "message": "Не удалось зарезервировать товар. Возможно, он закончился.",
  "details": {
    "product_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d"
  }
}
```
## 3. Webhook от платёжного шлюза
**`POST /payments/webhook`**

**Назначение:** получить уведомление об успешной или неуспешной оплате от Payment Gateway. Вызывается самим шлюзом, не клиентом.

### Request (успешная оплата)
```json
{
  "event": "payment.success",
  "payment_id": "p1p2p3p4-q5r6-7s8t-9u0v-1w2x3y4z5a6b",
  "order_id": "o1o2o3o4-p5q6-7r8s-9t0u-1v2w3x4y5z6a",
  "amount": 12470.00,
  "currency": "RUB",
  "external_id": "pay_abc123xyz",
  "timestamp": "2026-10-07T12:05:00Z",
  "signature": "sha256=8f14e45fceea167a5a36dedd4bea2543..."
}
```
### Request (неуспешная оплата)
```json
{
  "event": "payment.failed",
  "payment_id": "p1p2p3p4-q5r6-7s8t-9u0v-1w2x3y4z5a6b",
  "order_id": "o1o2o3o4-p5q6-7r8s-9t0u-1v2w3x4y5z6a",
  "amount": 12470.00,
  "currency": "RUB",
  "reason": "INSUFFICIENT_FUNDS",
  "timestamp": "2026-10-07T12:05:00Z",
  "signature": "sha256=..."
}
```
### Response 200
```json
{
  "status": "ok"
}
```
Логика обработки webhook
Проверить подпись signature — убедиться, что запрос пришёл от Payment Gateway.

Найти заказ по order_id.

Если payment.success:

Обновить статус заказа на PAID.

Подтвердить заказ в ERP (резерв → отгрузка).

Опубликовать событие order.confirmed в Kafka.

Если payment.failed:

Обновить статус заказа на PAYMENT_FAILED.

Опубликовать событие payment.failed в Kafka.

Клиент может повторить оплату или отменить заказ.

Вернуть 200 OK — чтобы Payment Gateway не повторял webhook.

Идемпотентность: если webhook приходит повторно с тем же payment_id, обработка не должна создавать дубли. Проверка по payment_id перед обновлением статуса.

## 4. Отмена заказа
**`POST /checkout/cancel`**

**Назначение:** отменить заказ. Если оплата уже прошла — инициировать возврат средств.

### Request
```json
{
  "order_id": "o1o2o3o4-p5q6-7r8s-9t0u-1v2w3x4y5z6a",
  "reason": "CUSTOMER_REQUEST"
}
```
### Response 200 (отмена после неуспешной оплаты)
```json
{
  "order_id": "o1o2o3o4-p5q6-7r8s-9t0u-1v2w3x4y5z6a",
  "status": "CANCELLED",
  "refund_required": false
}
```
### Response 200 (отмена после успешной оплаты)
```json
{
  "order_id": "o1o2o3o4-p5q6-7r8s-9t0u-1v2w3x4y5z6a",
  "status": "CANCELLED",
  "refund_required": true,
  "refund_amount": 12470.00,
  "refund_status": "PENDING",
  "estimated_refund_days": 5
}
```
### Response 409 (отмена невозможна)
```json
{
  "error": "CANCELLATION_NOT_ALLOWED",
  "message": "Заказ уже передан курьеру и не может быть отменён",
  "order_id": "o1o2o3o4-p5q6-7r8s-9t0u-1v2w3x4y5z6a",
  "status": "IN_TRANSIT"
}
```
## Коды ответов

| Код | Значение |
|-----|----------|
| 200 | Успешный запрос |
| 201 | Объект создан |
| 400 | Ошибка валидации входных данных |
| 401 | Не авторизован (отсутствует или неверный токен) |
| 403 | Доступ запрещён |
| 404 | Ресурс не найден |
| 409 | Конфликт (нет на складе, слот недоступен, отмена невозможна) |
| 500 | Внутренняя ошибка сервиса |
| 503 | Сервис временно недоступен (ERP, Payment Gateway) |

---

## Общие принципы

- **Аутентификация:** Bearer-токен в заголовке `Authorization: Bearer <token>`.
- **Идемпотентность:** для `POST /checkout/confirm` используется заголовок `Idempotency-Key` — повторный запрос с тем же ключом вернёт тот же результат.
- **Версионирование:** версия API указывается в URL (`/api/v1/...`).
- **Формат ошибок:** все ошибки возвращаются в едином формате `{ "error", "message", "details" }`.
- **Rate limiting:** 100 запросов в минуту на пользователя.
- **Таймауты:** внешние вызовы (ERP, Payment Gateway) — 5 секунд с одним retry.
