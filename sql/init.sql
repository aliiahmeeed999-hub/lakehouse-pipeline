CREATE SCHEMA IF NOT EXISTS public;

CREATE TABLE IF NOT EXISTS public.orders (
  order_id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL,
  product_code VARCHAR(50) NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
  order_status VARCHAR(20) NOT NULL DEFAULT 'NEW',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_updated_at ON public.orders;
CREATE TRIGGER trg_set_updated_at
BEFORE UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.orders (customer_id, product_code, quantity, unit_price, order_status)
VALUES
  (1001, 'LAPTOP-A1', 1, 1299.99, 'NEW'),
  (1002, 'MOUSE-MX', 2, 49.95, 'NEW'),
  (1003, 'KEYBOARD-K2', 1, 89.50, 'PROCESSING')
ON CONFLICT DO NOTHING;
