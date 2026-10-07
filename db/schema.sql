-- ============================================================
-- Схема БД: E-commerce Checkout System
-- СУБД: PostgreSQL 14+
-- Назначение: хранение заказов, корзин, платежей, доставок и остатков
-- ============================================================

-- ============================================================
-- 1. ТОВАРЫ И СКЛАДЫ
-- ============================================================

CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    price           NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    weight_kg       NUMERIC(8, 2) NOT NULL CHECK (weight_kg > 0),
    dimensions      JSONB,                       -- {"length": 100, "width": 50, "height": 75}
    category        VARCHAR(64),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE products IS 'Каталог товаров';
COMMENT ON COLUMN products.dimensions IS 'Габариты для расчёта доставки (JSONB)';

CREATE INDEX idx_products_category ON products(category) WHERE is_active = TRUE;


CREATE TABLE warehouses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    address         JSONB NOT NULL,              -- {"city": "...", "street": "...", "house": "..."}
    region          VARCHAR(64) NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE warehouses IS 'Склады и распределительные центры';


CREATE TABLE stock (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    warehouse_id    UUID NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    quantity        INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    reserved        INTEGER NOT NULL DEFAULT 0 CHECK (reserved >= 0),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_stock_product_warehouse UNIQUE (product_id, warehouse_id)
);

COMMENT ON TABLE stock IS 'Остатки товаров на складах';
COMMENT ON COLUMN stock.reserved IS 'Зарезервировано под активные заказы';

CREATE INDEX idx_stock_product ON stock(product_id);


-- ============================================================
-- 2. КОРЗИНА
-- ============================================================

CREATE TABLE carts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    status          VARCHAR(16) NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE', 'CHECKED_OUT', 'ABANDONED')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE carts IS 'Корзины пользователей';
COMMENT ON COLUMN carts.status IS 'ACTIVE — активная, CHECKED_OUT — оформлена, ABANDONED — брошена';

CREATE INDEX idx_carts_user ON carts(user_id);
CREATE INDEX idx_carts_status ON carts(status);


CREATE TABLE cart_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id         UUID NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES products(id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    added_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_cart_items UNIQUE (cart_id, product_id)
);

COMMENT ON TABLE cart_items IS 'Позиции корзины';

CREATE INDEX idx_cart_items_cart ON cart_items(cart_id);


-- ============================================================
-- 3. ЗАКАЗЫ
-- ============================================================

CREATE TABLE orders (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL,
    cart_id                 UUID REFERENCES carts(id),
    status                  VARCHAR(32) NOT NULL DEFAULT 'DRAFT'
                            CHECK (status IN (
                                'DRAFT',
                                'PENDING_PAYMENT',
                                'PAID',
                                'CONFIRMED',
                                'CANCELLED',
                                'PAYMENT_FAILED',
                                'EXPIRED'
                            )),
    subtotal                NUMERIC(12, 2) NOT NULL CHECK (subtotal >= 0),
    delivery_amount         NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (delivery_amount >= 0),
    total_amount            NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
    currency                CHAR(3) NOT NULL DEFAULT 'RUB',
    reservation_expires_at  TIMESTAMPTZ,           -- момент истечения резерва (15 мин)
    idempotency_key         VARCHAR(128) UNIQUE,   -- защита от дублей при повторном запросе
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE orders IS 'Заказы пользователей';
COMMENT ON COLUMN orders.reservation_expires_at IS 'Время истечения резерва товара';
COMMENT ON COLUMN orders.idempotency_key IS 'Ключ идемпотентности для POST /checkout/confirm';

CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created ON orders(created_at DESC);


CREATE TABLE order_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES products(id),
    warehouse_id    UUID NOT NULL REFERENCES warehouses(id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    price           NUMERIC(12, 2) NOT NULL CHECK (price >= 0),  -- цена на момент заказа
    status          VARCHAR(16) NOT NULL DEFAULT 'RESERVED'
                    CHECK (status IN ('RESERVED', 'SHIPPED', 'CANCELLED')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE order_items IS 'Позиции заказа';
COMMENT ON COLUMN order_items.price IS 'Цена зафиксирована на момент оформления заказа';

CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_warehouse ON order_items(warehouse_id);


-- ============================================================
-- 4. ПЛАТЕЖИ
-- ============================================================

CREATE TABLE payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    amount          NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    currency        CHAR(3) NOT NULL DEFAULT 'RUB',
    status          VARCHAR(16) NOT NULL DEFAULT 'INIT'
                    CHECK (status IN ('INIT', 'PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')),
    method          VARCHAR(16) NOT NULL
                    CHECK (method IN ('CARD', 'SBP', 'WALLET')),
    external_id     VARCHAR(128),                 -- ID платежа в платёжном шлюзе
    failure_reason  VARCHAR(64),                  -- INSUFFICIENT_FUNDS, CARD_DECLINED и т.п.
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE payments IS 'Платежи по заказам';
COMMENT ON COLUMN payments.external_id IS 'Идентификатор платежа в Payment Gateway (для идемпотентности webhook)';

CREATE INDEX idx_payments_order ON payments(order_id);
CREATE INDEX idx_payments_external ON payments(external_id);
CREATE INDEX idx_payments_status ON payments(status);


-- ============================================================
-- 5. ДОСТАВКА
-- ============================================================

CREATE TABLE deliveries (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id          UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    address           JSONB NOT NULL,             -- {"city": "...", "street": "...", "house": "...", "postal_code": "..."}
    slot_start        TIMESTAMPTZ NOT NULL,
    slot_end          TIMESTAMPTZ NOT NULL,
    courier_service   VARCHAR(64),                -- СДЭК, Boxberry, DPD и т.п.
    tracking_number   VARCHAR(128),
    status            VARCHAR(16) NOT NULL DEFAULT 'PENDING'
                      CHECK (status IN ('PENDING', 'ASSIGNED', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED')),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE deliveries IS 'Доставки заказов';
COMMENT ON COLUMN deliveries.slot_start IS 'Начало интервала доставки';
COMMENT ON COLUMN deliveries.slot_end IS 'Конец интервала доставки';

CREATE INDEX idx_deliveries_order ON deliveries(order_id);
CREATE INDEX idx_deliveries_status ON deliveries(status);
CREATE INDEX idx_deliveries_tracking ON deliveries(tracking_number);


-- ============================================================
-- 6. ТРИГГЕРЫ: автообновление updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_deliveries_updated_at
    BEFORE UPDATE ON deliveries
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_carts_updated_at
    BEFORE UPDATE ON carts
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_stock_updated_at
    BEFORE UPDATE ON stock
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- 7. ПРИМЕРЫ ЗАПРОСОВ
-- ============================================================

-- Получить активную корзину пользователя с товарами
-- SELECT c.id, ci.product_id, p.name, ci.quantity, p.price
-- FROM carts c
-- JOIN cart_items ci ON ci.cart_id = c.id
-- JOIN products p ON p.id = ci.product_id
-- WHERE c.user_id = '<uuid>' AND c.status = 'ACTIVE';

-- Проверить доступный остаток товара на складе
-- SELECT quantity - reserved AS available
-- FROM stock
-- WHERE product_id = '<uuid>' AND warehouse_id = '<uuid>';

-- Получить все заказы пользователя с последним статусом платежа
-- SELECT o.id, o.status, o.total_amount, p.status AS payment_status
-- FROM orders o
-- LEFT JOIN payments p ON p.order_id = o.id
-- WHERE o.user_id = '<uuid>'
-- ORDER BY o.created_at DESC;

-- Найти зависшие заказы (резерв истёк, оплата не прошла)
-- SELECT id, user_id, reservation_expires_at
-- FROM orders
-- WHERE status = 'PENDING_PAYMENT'
--   AND reservation_expires_at < NOW();
