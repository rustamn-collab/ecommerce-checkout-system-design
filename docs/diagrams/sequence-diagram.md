# Sequence-диаграмма: Оформление заказа

Диаграмма описывает взаимодействие фронтенда, микросервисов, ERP, платёжного шлюза и Kafka при оформлении заказа с курьерской доставкой и онлайн-оплатой.

## Основной сценарий

![Sequence Diagram](sequence-diagram.png)

## Что отображено на диаграмме

- **Синхронные вызовы:** Frontend → API Gateway → Cart Service → ERP / Logistics Service.
- **Асинхронные события:** Checkout Service → Kafka → Notification Service / Logistics Service.
- **Webhook:** Payment Gateway → Checkout Service (уведомление об оплате).
- **Альтернативные сценарии:** товара нет на складе; оплата отклонена.

## Исходник

Файл PlantUML: [sequence-diagram.puml](sequence-diagram.puml)
